import json
import logging
import os
import re
import requests

from collections import Counter

# the following try/except block will make the custom check compatible with any Agent version
try:
    # first, try to import the base class from old versions of the Agent...
    from checks import AgentCheck
except ImportError:
    # ...if the above failed, the check is running in Agent version 6 or later
    from datadog_checks.checks import AgentCheck

# content of the special variable __version__ will be shown in the Agent status page
__version__ = "1.0.0"


class ReviewEnvsCheck(AgentCheck):
    def __init__(self, *args, **kwargs):
        super(ReviewEnvsCheck, self).__init__(*args, **kwargs)

        # get configuration from ENV vars
        self.environment = os.environ['DD_ENVIRONMENT']
        self.heroku_team_name = os.environ['HEROKU_TEAM_NAME']
        self.heroku_api_token = os.environ['HEROKU_API_TOKEN']
        self.app_names = os.environ['HEROKU_APP_NAMES'].split(',')

        self.page_size = 500
        self.heroku_api_url = 'https://api.heroku.com'
        self.heroku_headers = {
            'Accept': 'application/vnd.heroku+json; version=3.review-apps',
            'Authorization': 'Bearer %s' % self.heroku_api_token,
            'User-Agent': 'Heroku GitHub Actions Provider by TheRealReal',
            'Content-Type': 'application/json',
            'Range': 'id ..; max=%d;' % self.page_size
            }

    def heroku_paginated_get_json_array( self, url, **kwargs ):
        print( "GET %s (Range: '%s')" % (url, kwargs['headers']['Range'] if 'Range' in kwargs['headers'] else '' ) )
        r = requests.get( url, **kwargs )
        results = json.loads(r.text)

        if r.status_code == 206:
            # recurse and return merged results
            kwargs['headers']['Range'] = r.headers['Next-Range']
            return results + self.heroku_paginated_get_json_array( url, **kwargs )
        return results

    def get_apps(self):
        apps = self.heroku_paginated_get_json_array(self.heroku_api_url+'/apps', headers=self.heroku_headers)
        try:
            if apps[0] is not None and 'id' in apps[0]:
                return apps
        except:
            pass
        return None

    def count_review_envs(self, apps):
        return len( set( [ '-'.join(a['name'].split('-')[1:4]) for a in apps if '-pr-' in a['name'] ] ) )

    def count_originating_apps(self, apps):
        return Counter( [ a['name'].split('-')[1] for a in apps if '-pr-' in a['name'] and re.search(r'\d+$',a['name']) ] )

    def check(self, instance):
        apps = self.get_apps()
        self.gauge('review_envs.number_of_envs', self.count_review_envs(apps),
            tags=[
                'heroku_team:%s' % (self.heroku_team_name),
                'environment:%s' % (self.environment)
            ])
        # count how many origin apps exist of each type
        origin_app_counts = self.count_originating_apps(apps)
        for app_type in self.app_names:
            self.gauge('review_envs.number_of_originating_apps', origin_app_counts[app_type],
                tags=[
                    'heroku_team:%s' % (self.heroku_team_name),
                    'environment:%s' % (self.environment),
                    'origin_app:%s' % (app_type)
                ])

