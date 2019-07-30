import json
import os
import re
import requests

# the following try/except block will make the custom check compatible with any Agent version
try:
    # first, try to import the base class from old versions of the Agent...
    from checks import AgentCheck
except ImportError:
    # ...if the above failed, the check is running in Agent version 6 or later
    from datadog_checks.checks import AgentCheck

# content of the special variable __version__ will be shown in the Agent status page
__version__ = "1.0.0"


class SalesforceLimitsCheck(AgentCheck):
    def __init__(self, *args, **kwargs):
        super(SalesforceLimitsCheck, self).__init__(*args, **kwargs)

        # get configuration from ENV vars
        self.environment = os.environ['DD_ENVIRONMENT']
        self.base_url = os.environ['SALESFORCE_BASE_URL']
        self.client_id = os.environ['SALESFORCE_CLIENT_ID']
        self.refresh_token = os.environ['SALESFORCE_REFRESH_TOKEN']
        self.api_version = os.environ['SALESFORCE_API_VERSION']

        # this is the salesforce instance for passing in to as a tag
        self.sfdc_domain = re.sub('[^a-zA-Z0-9_]','_',re.match("https://([^/]+)(/|$)",self.base_url).group(1))

    def poll_limits(self):
        auth_response = requests.post( self.base_url+"/services/oauth2/token",
            data={'client_id': self.client_id, 'refresh_token': self.refresh_token, 'grant_type': 'refresh_token'})
        auth = json.loads( auth_response.text )

        if auth_response.status_code == 200 and 'access_token' in auth:
            print( "Successfully authorized to SFDC." )
            token=auth['access_token']

            limits_response = requests.get( self.base_url+"/services/data/v%s/limits/" % self.api_version,
                headers={'Authorization': 'Bearer %s' % token} )
            limits = json.loads( limits_response.text )

            if limits_response.status_code == 200 and 'DailyApiRequests' in limits:
                print( "Parsed limits from SFDC API response." )

                print( "Max requests: %s; Remaining requests: %s" % (limits['DailyApiRequests']['Max'],limits['DailyApiRequests']['Remaining']))
                return limits
            else:
                print( "Couldn't parse limits from SFDC API response." )
        else:
            print( "Login to SFDC unsuccessful." )
        return None

    def check(self, instance):
        limits = self.poll_limits()
        if limits is not None:
            self.gauge('salesforce.limits.daily_api_requests.max', limits['DailyApiRequests']['Max'],
                tags=[
                    'sfdc_instance:%s' % (self.sfdc_domain),
                    'environment:%s' % (self.environment)
                ])
            self.gauge('salesforce.limits.daily_api_requests.remaining', limits['DailyApiRequests']['Remaining'],
                tags=[
                    'sfdc_instance:%s' % (self.sfdc_domain),
                    'environment:%s' % (self.environment)
                ])
