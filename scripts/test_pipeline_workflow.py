#!/usr/bin/env python3
"""SONNY-3571: preserve the branch-pipeline mitigation for missing MR needs."""

import copy
import re
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]


def condition_matches(expression, variables):
    """Evaluate only the predicates used by this workflow; reject new syntax."""
    for term in expression.split(" && "):
        match = re.fullmatch(r'\$([A-Z_]+)(?: (==|!=) (\$[A-Z_]+|"[^"]*"))?', term)
        if match is None:
            raise ValueError(f"unsupported workflow predicate: {term}")
        name, operator, operand = match.groups()
        value = variables.get(name, "")
        if operator is None:
            matched = bool(value)
        else:
            other = (
                variables.get(operand[1:], "")
                if operand.startswith("$")
                else operand[1:-1]
            )
            matched = (value == other) if operator == "==" else (value != other)
        if not matched:
            return False
    return True


def decision(workflow, variables):
    for rule in workflow["rules"]:
        if "if" not in rule or condition_matches(rule["if"], variables):
            auto_cancel = dict(workflow.get("auto_cancel", {}))
            auto_cancel.update(rule.get("auto_cancel", {}))
            return rule.get("when", "always") != "never", auto_cancel
    return False, {}


def context(source, branch="", tag=""):
    return {
        "CI_PIPELINE_SOURCE": source,
        "CI_COMMIT_BRANCH": branch,
        "CI_COMMIT_TAG": tag,
        "CI_DEFAULT_BRANCH": "main",
    }


class WorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config = yaml.safe_load((ROOT / ".gitlab-ci.yml").read_text())

    def test_context_matrix(self):
        cases = [
            (context("merge_request_event"), False),
            (context("push", "feature/sonny-3571"), True),
            (context("push", "main"), True),
            (context("push", tag="v0.1.0"), True),
            (context("schedule", "main"), True),
            (context("web", "feature/sonny-3571"), True),
        ]
        for variables, allowed in cases:
            with self.subTest(variables=variables):
                self.assertEqual(
                    decision(self.config["workflow"], variables)[0], allowed
                )

    def test_auto_cancel_preserved(self):
        for variables in [context("push", "feature"), context("push", "main")]:
            self.assertEqual(
                decision(self.config["workflow"], variables)[1],
                {
                    "on_job_failure": "all",
                    "on_new_commit": "interruptible",
                },
            )
        self.assertEqual(
            decision(self.config["workflow"], context("push", tag="v0.1.0"))[1][
                "on_new_commit"
            ],
            "none",
        )

    def test_dependency_remains_required_in_admitted_branch_pipeline(self):
        self.assertIn("build", self.config)
        self.assertEqual(self.config["build"]["stage"], "build")
        needs = self.config["bench-regression"]["needs"]
        required = [
            item if isinstance(item, str) else item["job"]
            for item in needs
            if isinstance(item, str) or not item.get("optional", False)
        ]
        self.assertIn("build", required)
        self.assertTrue(decision(self.config["workflow"], context("push", "main"))[0])

    def test_removing_mr_block_reproduces_admission_bug(self):
        workflow = copy.deepcopy(self.config["workflow"])
        workflow["rules"] = [
            rule
            for rule in workflow["rules"]
            if rule.get("if") != '$CI_PIPELINE_SOURCE == "merge_request_event"'
        ]
        self.assertTrue(decision(workflow, context("merge_request_event"))[0])
        self.assertFalse(
            decision(self.config["workflow"], context("merge_request_event"))[0]
        )

    def test_earlier_catch_all_reproduces_admission_bug(self):
        workflow = copy.deepcopy(self.config["workflow"])
        workflow["rules"].insert(0, {"when": "always"})
        self.assertTrue(decision(workflow, context("merge_request_event"))[0])
        self.assertFalse(
            decision(self.config["workflow"], context("merge_request_event"))[0]
        )

    def test_predicate_parser_rejects_unhandled_syntax(self):
        with self.assertRaises(ValueError):
            condition_matches("$CI_COMMIT_BRANCH =~ /main/", context("push", "main"))
        self.assertFalse(condition_matches("$CI_COMMIT_TAG", context("push", "main")))
        self.assertTrue(
            condition_matches("$CI_COMMIT_TAG", context("push", tag="v0.1.0"))
        )


if __name__ == "__main__":
    unittest.main()
