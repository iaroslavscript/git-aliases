#!/usr/bin/env python3

from argparse import ArgumentParser, Namespace
import dataclasses
import json
import os
import re
from urllib3.util import Retry
import sys
from typing import Any, Union, Callable

from github import Auth
from github import Github
from github.Issue import Issue as Gissue
from github.PullRequest import PullRequest as Gpr
from github.Repository import Repository as Grepository



env_prefix: str = 'GITHUB_CLI_'


@dataclasses.dataclass
class Issue:
    id: Union[str, None]
    summary: Union[str, None]


@dataclasses.dataclass
class PullRequest:
    id: Union[str, None]
    summary: Union[str, None]


@dataclasses.dataclass
class Config:
    # common fields
    url: Union[str, None]
    remote_url: Union[str, None]
    repository: Union[str, None]
    token: Union[str, None]

    # action function
    action_cmd: Union[Callable, None]

    # action fields: issue-show
    issue_id: Union[str, None]

    # action fields: issue-create, pr-create
    summary: Union[str, None]


class GitHubClient:

    def __init__(self, gh: Github, repository: str):
        self._gh: Github = gh
        self._repository: str = repository

    def issueShow(self, issue: Issue) -> Issue:

        repo: Grepository = self._gh.get_repo(self._repository)
        gissue: Gissue = repo.get_issue(number=int(issue.id))
        summary: str = gissue.title

        return dataclasses.replace(issue, summary=summary)

    def issueCreate(self, issue: Issue) -> Issue:

        grepo: Grepository = self._gh.get_repo(self._repository)
        gissue = grepo.create_issue(title=issue.summary, body="This is the issue body")

        return issue_builder(str(gissue.number), gissue.title)
    
    def prCreate(self, pr: PullRequest) -> PullRequest:

        repo: Grepository = self._gh.get_repo(self._repository)
        #repo.create_pull()

        #create_pull(base: str, head: str, *, title: Union[str, github.GithubObject._NotSetType] = NotSet, body: Union[str, github.GithubObject._NotSetType] = NotSet, maintainer_can_modify: Union[bool, github.GithubObject._NotSetType] = NotSet, draft: Union[bool, github.GithubObject._NotSetType] = NotSet, issue: Union[github.Issue.Issue, github.GithubObject._NotSetType] = NotSet) → github.PullRequest.PullRequest
        raise NotImplementedError()


def main(env:dict[str, str], argv: list[str]):
    
    default_cfg = config_builder()
    cfg = config_builder_from_env(default_cfg, env)
    parser = argparse_builder(cfg)
    args = parser.parse_args(argv)
    cfg = config_builder_from_args(cfg, args)
    cfg = process_config_values(cfg)

    gh = github_client_builder(cfg)

    if cfg.action_cmd is None:
        parser.print_help()
        sys.exit(1)

    cfg.action_cmd(cfg, gh)

    return 0


def issue_builder(id: str, summary: str) -> Issue:

    return Issue(id, summary)


def pr_builder(id: str, summary: str) -> PullRequest:

    return PullRequest(id, summary)


def config_builder() -> Config:

    cfg = Config(
        None,
        None,
        None,
        None,
        None,
        None,
        None,
    )

    return cfg


def config_builder_from_env(default_cfg: Config, env: dict[str, str]) -> Config:

    cfg = dataclasses.replace(default_cfg)
    cfg.url = env.get(env_prefix + 'URL', cfg.url)
    cfg.remote_url = env.get(env_prefix + 'REMOTE_URL', cfg.url)
    cfg.token = env.get(env_prefix + 'TOKEN', cfg.token)

    return cfg


def config_builder_from_args(default_cfg: Config, args: Namespace) -> Config:

    cfg = dataclasses.replace(default_cfg)
    cfg.url = args.url if args.url is not None else cfg.url
    cfg.remote_url = args.remote_url if args.remote_url is not None else cfg.remote_url
    cfg.token = args.token if args.token is not None else cfg.token

    if args.action_cmd == 'issue-show':
        cfg.action_cmd = run_action_issue_show
        cfg.issue_id = args.issue_id
    elif args.action_cmd == 'issue-create':
        cfg.action_cmd = run_action_issue_create
        cfg.summary = args.summary
    elif args.action_cmd == 'pr-create':
        cfg.action_cmd = run_action_pr_create
    else:
        raise ValueError(f'Unknown action command: {args.action_cmd}')

    return cfg


def argparse_builder(default_cfg: Config) -> ArgumentParser:

    parent_parser = ArgumentParser(add_help=False)#, allow_abbrev=False)

    parent_parser.add_argument('--url'), #required=(default_cfg.url is None))
    parent_parser.add_argument('--remote-url') #, required=(default_cfg.remote_url is None))
    parent_parser.add_argument('--token') #, required=(default_cfg.token is None))

    parser = ArgumentParser(parents=[parent_parser], description='Jira Client')
    subparsers = parser.add_subparsers(dest='action_cmd', help='sub-command help')

    parser_issue_summary: ArgumentParser = subparsers.add_parser('issue-show', parents=[parent_parser], help='Get issue summary')
    parser_issue_summary.add_argument('issue_id', help='Jura issue ID')

    parser_issue_create: ArgumentParser = subparsers.add_parser('issue-create', parents=[parent_parser], help='Create a new issue')
    parser_issue_create.add_argument('summary', help='Issue summary')

    parser_pr_create: ArgumentParser = subparsers.add_parser('pr-create', parents=[parent_parser], help='Create a new pull request')
    parser_pr_create.add_argument('summary', help='Pull request summary')

    return parser


def github_client_builder(cfg: Config) -> GitHubClient:

    retry: Retry = Retry(
        total=10,
        status_forcelist=(500, 502, 504),
        backoff_factor=0.3,
    )

    auth: Auth = Auth.Token(cfg.token)
    gh = Github(
        auth=auth,
        #base_url=f"https://{cfg.url}/api/v3",
        retry=retry,
    )

    return GitHubClient(gh, cfg.repository)


def run_action_issue_show(cfg: Config, gh_client: GitHubClient) -> None:
    issue = issue_builder(cfg.issue_id, None)
    print(format_json(gh_client.issueShow(issue)))


def run_action_issue_create(cfg: Config, gh_client: GitHubClient) -> None:
    issue = issue_builder(None, cfg.summary)
    print(format_json(gh_client.issueCreate(issue)))


def run_action_pr_create(cfg: Config, gh_client: GitHubClient) -> None:
    pr = pr_builder(None, cfg.summary)
    print(format_json(gh_client.prCreate(pr)))


def format_json(data: Any) -> str:

    return json.dumps(dataclasses.asdict(data), indent=2)


def process_config_values(cfg: Config) -> Config:
    
    return dataclasses.replace(
        cfg,
        repository=extract_repo_from_remote_url(cfg.remote_url),
    )


def extract_repo_from_remote_url(url: str) -> str:

    value: str = ""

    if (m := re.match(r'^git@([^:]+):(.+).git$', url)):
        value = m.group(2)
    else:
        raise ValueError(f"ERROR: Cannot parse remote url {url}")
        
    return value


if __name__ == '__main__':
    main(os.environ, sys.argv[1:])
