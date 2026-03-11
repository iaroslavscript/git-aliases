#!/usr/bin/env python3

from argparse import ArgumentParser, Namespace
import dataclasses
import json
import os
import sys
from typing import Any, Union, Callable

from atlassian import Jira


env_prefix: str = 'JIRA_CLI_'


@dataclasses.dataclass
class Issue:
    id: Union[str, None]
    summary: Union[str, None]


@dataclasses.dataclass
class Config:
    # common fields
    url: Union[str, None]
    remote_url: Union[str, None]
    token: Union[str, None]
    verify_ssl: Union[bool, None]

    # action function
    action_cmd: Union[Callable, None]

    # action fields: issue-show
    issue_id: Union[str, None]

    # action fields: issue-create
    summary: Union[str, None]


class JiraClient:

    def __init__(self, jira):
        self._jira = jira

    def issueShow(self, issue: Issue) -> Issue:

        issue_raw: dict[str, Any] = self._jira.issue(issue.id)
        summary: str = issue_raw.get('fields', {}).get('summary', '')

        return dataclasses.replace(issue, summary=summary)

    def issueCreate(self, issue: Issue) -> Issue:

        raise NotImplementedError()


def main(env:dict[str, str], argv: list[str]):
    
    default_cfg = config_builder()
    cfg = config_builder_from_env(default_cfg, env)
    parser = argparse_builder(cfg)
    args = parser.parse_args(argv)
    cfg = config_builder_from_args(cfg, args)

    jira = jira_client_builder(cfg)

    if cfg.action_cmd is None:
        parser.print_help()
        sys.exit(1)

    cfg.action_cmd(jira, cfg.issue_id)

    return 0


def issue_builder(id: str, summary: str) -> Issue:

    return Issue(id, summary)


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
    cfg.token = env.get(env_prefix + 'TOKEN', cfg.token)
    cfg.verify_ssl = env.get(env_prefix + 'VERIFY_SSL', cfg.verify_ssl)

    return cfg


def config_builder_from_args(default_cfg: Config, args: Namespace) -> Config:

    cfg = dataclasses.replace(default_cfg)
    cfg.url = args.url
    cfg.remote_url = args.remote_url
    cfg.token = args.token
    cfg.verify_ssl = args.verify_ssl

    if args.action_cmd == 'issue-summary':
        cfg.action_cmd = run_action_issue_show
        cfg.issue_id = args.issue_id
    elif args.action_cmd == 'issue-create':
        cfg.action_cmd = run_action_issue_create
    else:
        raise ValueError(f'Unknown action command: {args.action_cmd}')

    return cfg


def argparse_builder(default_cfg: Config) -> ArgumentParser:

    parent_parser = ArgumentParser(add_help=False, allow_abbrev=False)

    parent_parser.add_argument('--url', required=(default_cfg.url is None), default=default_cfg.url)
    parent_parser.add_argument('--remote-url', required=(default_cfg.remote_url is None), default=default_cfg.remote_url)
    parent_parser.add_argument('--token', required=(default_cfg.token is None))
    parent_parser.add_argument('--verify-ssl', required=(default_cfg.verify_ssl is None),
                               type=bool,
                               nargs='?',
                               const=True,
                               default=default_cfg.verify_ssl)
    
    parser = ArgumentParser(parents=[parent_parser], description='Jira Client')
    subparsers = parser.add_subparsers(dest='action_cmd', help='sub-command help')

    parser_issue_summary: ArgumentParser = subparsers.add_parser('issue-show', parents=[parent_parser], help='Get issue summary')
    parser_issue_summary.add_argument('issue-id', help='Jura issue ID')

    parser_issue_create: ArgumentParser = subparsers.add_parser('issue-create', parents=[parent_parser], help='Create a new issue')
    parser_issue_create.add_argument('summary', help='Issue summary')

    return parser


def jira_client_builder(cfg: Config) -> JiraClient:

    jira = Jira(
        url=cfg.url,
        token=cfg.token,
        # verify=cfg.verify_ssl,    # TODO FIXME
    )

    return JiraClient(jira)


def run_action_issue_show(cfg: Config, jira_client: JiraClient) -> None:
    issue = issue_builder(cfg.issue_id, None)
    print(format_json(jira_client.issueShow(issue)))


def run_action_issue_create(cfg: Config, jira_client: JiraClient) -> None:
    issue = issue_builder(None, cfg.summary)
    print(format_json(jira_client.issueCreate(issue)))


def format_json(data: Any) -> str:
    return json.dumps(data, indent=2)


if __name__ == '__main__':
    main(os.environ, sys.argv[1:])
