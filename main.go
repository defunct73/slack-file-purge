// +build !test

package main

import (
	"context"
	"os"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-lambda-go/lambdacontext"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/ssm"
	"github.com/go-kit/kit/log"
	"github.com/nlopes/slack"
)

func main() {
	var (
		logger = log.With(
			log.NewLogfmtLogger(log.NewSyncWriter(os.Stdout)),
			"ts", log.DefaultTimestampUTC(),
		)
		ssmSvc = ssm.New(session.Must(session.NewSession()))
	)
	lambda.Start(func(ctx context.Context, event *Event) error {
		lc, _ := lambdacontext.FromContext(ctx)
		token, err := slackOAuthToken(ctx, ssmSvc)
		if err != nil {
			return err
		}
		h := handler{
			logger:  log.With(logger, "request_id", lc.AwsRequestID),
			slackCl: slack.New(token),
		}
		return h.Handle(ctx, event)
	})
}
