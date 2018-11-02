package main

import (
	"context"
	"fmt"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/ssm"
	"github.com/aws/aws-sdk-go/service/ssm/ssmiface"
	"github.com/go-kit/kit/log"
	"github.com/go-kit/kit/log/level"
	"github.com/nlopes/slack"
)

// Event is the custom JSON payload required by this lambda.
type Event struct {
	ExcludedChannels []string `json:"excluded_channels"`
}

// The Lambda handler.
type handler struct {
	logger  log.Logger
	slackCl *slack.Client
}

// The Lambda entry point. All errors are logged, but always returns nil to
// prevent re-triggering.
func (h *handler) Handle(ctx context.Context, event *Event) error {
	files, err := h.getFiles(ctx)
	if err != nil {
		level.Error(h.logger).Log("msg", "failed to list files", "error", err)
		return nil
	}

	level.Info(h.logger).Log("msg", fmt.Sprintf("processing %d files", len(files)))

	purged := 0

	for _, file := range files {
		if keepFile(event.ExcludedChannels, file) {
			level.Info(h.logger).Log("msg", fmt.Sprintf("keeping %s", file.Name))
			continue
		}

		level.Info(h.logger).Log("msg", fmt.Sprintf("deleting %s", file.Name))

		if err = h.slackCl.DeleteFileContext(ctx, file.ID); err != nil {
			level.Error(h.logger).Log(
				"msg", "failed to delete file",
				"file", file.Name,
				"error", err,
			)
			continue
		}

		purged++
	}

	level.Info(h.logger).Log("msg", fmt.Sprintf("purged %d files", purged))

	return nil
}

func (h *handler) getFiles(ctx context.Context) ([]slack.File, error) {
	page := 1
	allFiles := []slack.File{}
	for {
		files, pages, err := h.slackCl.GetFilesContext(ctx, slack.GetFilesParameters{
			Count:       100,
			Page:        page,
			TimestampTo: slack.JSONTime(time.Now().AddDate(0, 0, -14).Unix()),
		})
		if err != nil {
			return nil, err
		}

		level.Info(h.logger).Log(
			"current_page", page,
			"total_pages", pages.Pages,
		)

		if page == pages.Pages || pages.Pages == 0 {
			break
		}

		page = pages.Page + 1
		allFiles = append(allFiles, files...)

	}
	return allFiles, nil
}

func keepFile(channels []string, file slack.File) bool {
	for _, ch := range file.Channels {
		for _, exCh := range channels {
			if exCh == ch {
				return true
			}
		}
	}
	return false
}

func slackOAuthToken(ctx context.Context, svc ssmiface.SSMAPI) (string, error) {
	rsp, err := svc.GetParameterWithContext(ctx, &ssm.GetParameterInput{
		Name:           aws.String("/insurrection-slack-team/oauth-token"),
		WithDecryption: aws.Bool(true),
	})
	if err != nil {
		return "", err
	}
	return aws.StringValue(rsp.Parameter.Value), nil
}
