"""Integration tests for ML semantic security layer.

Verify ML validators are correctly wired into guard pipelines.
Do NOT require models to be loaded — test plumbing, not inference.
"""
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'scripts'))

import pytest


class TestMLPipelineIntegration:

    def test_guard_definitions_import(self):
        from guard_definitions import GUARD_PIPELINES
        assert len(GUARD_PIPELINES) == 4

    def test_all_modes_have_ml(self):
        from guard_definitions import GUARD_PIPELINES
        for mode in ('memory', 'exfil', 'inbound', 'write'):
            vtypes = [v[0] for v in GUARD_PIPELINES[mode]]
            assert 'custom:SentinelV2Detector' in vtypes, f"{mode} missing SentinelV2Detector"
            assert 'custom:PromptGuard2Detector' in vtypes, f"{mode} missing PromptGuard2Detector"

    def test_config_loads(self):
        from validators import _load_ml_config
        config = _load_ml_config()
        assert 'ml_sentinel_v2' in config
        assert 'ml_prompt_guard_2' in config
        assert 'ml_ensemble_mode' in config

    def test_ensemble_module_imports(self):
        from ml_ensemble import apply_ensemble_policy
        result = apply_ensemble_policy(
            sentinel_flags=False, sentinel_score=0.1,
            pg2_flags=False, pg2_score=0.1,
            mode='block'
        )
        assert result['blocked'] is False

    def test_bash_ast_module_imports(self):
        from bash_ast import extract_strings, has_eval_or_source
        assert has_eval_or_source('eval foo') is True
        assert has_eval_or_source('echo foo') is False

    def test_validators_register_all(self):
        from validators import register_validators
        v = register_validators()
        if v is None:
            pytest.skip("guardrails-ai not installed")
        expected = {'ExfilDetector', 'EncodingDetector', 'ForeignScriptDetector',
                    'AcrosticDetector', 'SentinelV2Detector', 'PromptGuard2Detector',
                    'EvalSourceEscalator'}
        assert expected.issubset(set(v.keys()))
