#!/usr/bin/env python3
"""Redact account/mail/user fields from a provenance JSON before it's committed.

Used by the analysis-data build tools. Kept identical in both repos.
"""
import re

# Redact KEYS whose name looks secret, and VALUES that look like account/mail flags or emails.
_SENS_KEY = re.compile(r"(account|mail|secret|token|password|passwd)", re.I)
_SENS_VAL = re.compile(r"(--?(account|mail[-_]?user|uid)\b|[\w.+-]+@[\w.-]+)", re.I)
REDACT = "<redacted>"


def sanitize_json(obj):
    """Recursively redact account/mail/user-ish keys and flag/email-style values. Keeps shape
    (so it's obvious a field existed and was scrubbed) and everything non-sensitive intact."""
    if isinstance(obj, dict):
        return {k: (REDACT if _SENS_KEY.search(k) else sanitize_json(v)) for k, v in obj.items()}
    if isinstance(obj, list):
        return [sanitize_json(x) for x in obj]
    if isinstance(obj, str) and _SENS_VAL.search(obj):
        return REDACT
    return obj
