# Go minimum version check.
GO_MIN_VERSION := 11000 # 1.10
GO_VERSION_CHECK := \
  $(shell expr \
    $(shell go version | \
      awk '{print $$3}' | \
      cut -do -f2 | \
      sed -e 's/\.\([0-9][0-9]\)/\1/g' -e 's/\.\([0-9]\)/0\1/g' -e 's/^[0-9]\{3,4\}$$/&00/' \
    ) \>= $(GO_MIN_VERSION) \
  )

# Default Go linker flags.
GO_LDFLAGS ?= -ldflags="-s -w"

# Build files.
FILE_PURGE   := bin/filepurge
SAM_TEMPLATE := sam_template.yaml

# Default stack settings.
# Override these by exporting them as environment variables.
ACCOUNT_ID       ?= $(shell aws sts get-caller-identity --output text --query 'Account')
AWS_REGION       ?= us-west-2
STACK_NAME       ?= slack-file-purge
ARTIFACTS_BUCKET ?= $(STACK_NAME)-$(ACCOUNT_ID)-$(AWS_REGION)

.PHONY: all
all: check-go clean $(FILE_PURGE)

$(FILE_PURGE):
	GOOS=linux GOARCH=amd64 go build $(GO_LDFLAGS) $(BUILDARGS) -o $@ ./...
	zip -j $@.zip $@

chkenv-%:
	@if [ "${${*}}" = "" ]; then \
		echo "Environment variable $* not set"; \
		exit 1; \
	fi

.PHONY: artifacts-bucket
artifacts-bucket:
	@aws s3 mb s3://$(ARTIFACTS_BUCKET)

.PHONY: update-oauth-token
update-oauth-token: chkenv-SLACK_OAUTH_TOKEN
	@aws ssm put-parameter \
	  --description "Insurrection Slack OAuth token" \
	  --name "/insurrection-slack-team/oauth-token" \
	  --value $(SLACK_OAUTH_TOKEN) \
	  --type SecureString \
	  --overwrite

.PHONY: package
package: check-go clean all
	aws cloudformation package \
	  --template-file template.yaml \
	  --output-template-file $(SAM_TEMPLATE) \
	  --s3-bucket $(ARTIFACTS_BUCKET)

.PHONY: deploy
deploy:
	aws cloudformation deploy \
	  --stack-name $(STACK_NAME) \
	  --template-file $(SAM_TEMPLATE) \
	  --capabilities CAPABILITY_NAMED_IAM

.PHONY: vendor
vendor:
	dep ensure

.PHONY: test
test: check-go
	go test $(TESTARGS) -timeout=30s ./...
	@$(MAKE) vet
	@$(MAKE) lint

.PHONY: vet
vet: check-go
	go vet $(VETARGS) ./...

.PHONY: lint
lint: check-go
	@echo "golint $(LINTARGS)"
	@for pkg in $(shell go list ./...) ; do \
		golint $(LINTARGS) $$pkg ; \
	done

.PHONY: cover
cover: check-go
	@$(MAKE) test TESTARGS="-tags test -race -coverprofile=coverage.out"
	@go tool cover -html=coverage.out
	@rm -f coverage.out

.PHONY: clean
clean:
	@rm -rf ./bin sam_template.yaml

.PHONY: check-go
check-go:
ifeq ($(GO_VERSION_CHECK),0)
	$(error go1.10 or higher is required)
endif