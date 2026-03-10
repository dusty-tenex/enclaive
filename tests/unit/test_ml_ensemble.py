"""Tests for ML ensemble disagreement policy."""
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'scripts'))

import pytest
from ml_ensemble import apply_ensemble_policy


class TestEnsemblePolicy:
    """Test ensemble disagreement resolution."""

    def test_both_flag_block_mode(self):
        result = apply_ensemble_policy(
            sentinel_flags=True, sentinel_score=0.95,
            pg2_flags=True, pg2_score=0.92,
            mode='block'
        )
        assert result['blocked'] is True
        assert result['severity'] == 'P0'

    def test_both_flag_pass_mode(self):
        result = apply_ensemble_policy(
            sentinel_flags=True, sentinel_score=0.95,
            pg2_flags=True, pg2_score=0.92,
            mode='pass'
        )
        assert result['blocked'] is True
        assert result['severity'] == 'P0'

    def test_one_flags_block_mode(self):
        result = apply_ensemble_policy(
            sentinel_flags=True, sentinel_score=0.90,
            pg2_flags=False, pg2_score=0.10,
            mode='block'
        )
        assert result['blocked'] is True
        assert result['severity'] == 'P0'

    def test_one_flags_pass_mode(self):
        result = apply_ensemble_policy(
            sentinel_flags=True, sentinel_score=0.90,
            pg2_flags=False, pg2_score=0.10,
            mode='pass'
        )
        assert result['blocked'] is False
        assert result['severity'] == 'P1'

    def test_neither_flags(self):
        result = apply_ensemble_policy(
            sentinel_flags=False, sentinel_score=0.10,
            pg2_flags=False, pg2_score=0.05,
            mode='block'
        )
        assert result['blocked'] is False
        assert result['severity'] is None

    def test_neither_available(self):
        result = apply_ensemble_policy(
            sentinel_flags=None, sentinel_score=None,
            pg2_flags=None, pg2_score=None,
            mode='block'
        )
        assert result['blocked'] is False

    def test_one_available_flags_block(self):
        result = apply_ensemble_policy(
            sentinel_flags=True, sentinel_score=0.92,
            pg2_flags=None, pg2_score=None,
            mode='block'
        )
        assert result['blocked'] is True
