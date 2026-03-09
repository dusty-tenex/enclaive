"""Tests for guard pipeline definitions."""
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'scripts'))
import pytest
from guard_definitions import GUARD_PIPELINES

class TestGuardPipelines:
    @pytest.mark.parametrize("mode", ["memory", "exfil", "inbound", "write"])
    def test_sentinel_v2_in_pipeline(self, mode):
        validators = [v[0] for v in GUARD_PIPELINES[mode]]
        assert "custom:SentinelV2Detector" in validators

    @pytest.mark.parametrize("mode", ["memory", "exfil", "inbound", "write"])
    def test_prompt_guard_2_in_pipeline(self, mode):
        validators = [v[0] for v in GUARD_PIPELINES[mode]]
        assert "custom:PromptGuard2Detector" in validators

    def test_exfil_has_ast_flag(self):
        for vtype, kwargs in GUARD_PIPELINES["exfil"]:
            if vtype == "custom:ExfilDetector":
                assert kwargs.get("use_ast") is True
                return
        pytest.fail("ExfilDetector not found in exfil pipeline")

    def test_exfil_has_eval_escalation(self):
        validators = [v[0] for v in GUARD_PIPELINES["exfil"]]
        assert "custom:EvalSourceEscalator" in validators
