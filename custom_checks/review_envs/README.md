salesforce_limits
=================

## Overview

DataDog custom check for monitoring the Salesforce Sales Cloud API Limit utilization on a single instance.

Constructor pulls environment variables for configuration, interval configured in the configuration file.

## Expected Environment Variables

| ENV var expected | example value |
| --- | --- |
| `DD_ENVIRONMENT` | `staging` or `production` |
| `SALESFORCE_BASE_URL` | `https://yoursfdcinstance.lightning.force.com` |
| `SALESFORCE_CLIENT_ID` | `clientid` |
| `SALESFORCE_REFRESH_TOKEN` | `refresh_token` |
| `SALESFORCE_API_VERSION` | `46.0` |

## Output Metrics

| metric key | explanation |
| --- | --- |
| `salesforce.limits.daily_api_requests.max` | `DailyApiRequests` / `Max` - size of the daily quota. |
| `salesforce.limits.daily_api_requests.remaining` | `DailyApiRequests` / `Remaining` - remaining API requests within daily quota. |

## Automatic Tagging

| tag key | tag value |
| --- | --- |
| `environment` | `staging` or `production` - directly from the `DD_ENVIRONMENT` variable. |
| `sfdc_instance` | `yoursfdcinstance_salesforce_com` - domain parsed from `SALESFORCE_BASE_URL`. |
