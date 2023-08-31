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
all: clean $(FILE_PURGE)

$(FILE_PURGE):
	GOOS=linux GOARCH=arm64 go build -buildvcs=false -trimpath -tags lambda.norpc $(GO_LDFLAGS) $(BUILDARGS) -o ./bin/bootstrap ./...

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
package: clean all
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
	go mod tidy
	go mod vendor

.PHONY: test
test:
	go test -buildvcs=false -race -timeout=30s $(TESTARGS) ./...
	@$(MAKE) vet
	@$(MAKE) lint

.PHONY: vet
vet:
	go vet -buildvcs=false $(VETARGS) ./...

.PHONY: lint
lint:
	staticcheck -tags -buildvcs=false $(LINTARGS) ./...

.PHONY: install-staticcheck
install-staticcheck:
	go install honnef.co/go/tools/cmd/staticcheck@latest

.PHONY: cover
cover:
	@$(MAKE) test TESTARGS="-tags test -race -coverprofile=coverage.out"
	@go tool cover -html=coverage.out
	@rm -f coverage.out

.PHONY: clean
clean:
	@rm -rf ./bin sam_template.yaml
