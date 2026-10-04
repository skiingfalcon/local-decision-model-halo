"""Make the corporate TLS-inspection chain (Cisco Umbrella) verifiable under Python 3.13.

Python 3.13 turns on ssl.VERIFY_X509_STRICT by default. Umbrella's re-signed leaf
certificates have no Authority Key Identifier, so strict mode rejects them even though
the chain verifies against the Umbrella root in state/certs/ca-bundle.pem.

Installed into the venv as a .pth hook by scripts/setup-tls.ps1. It does nothing unless
LOCAL_TLS_RELAX_STRICT=1. When enabled it clears only the strict flag, so chain,
hostname and expiry checks still apply.
"""

import os
import ssl

if os.environ.get("LOCAL_TLS_RELAX_STRICT") == "1" and hasattr(ssl, "VERIFY_X509_STRICT"):
    _orig = ssl.create_default_context

    def _create_default_context(*args, **kwargs):
        ctx = _orig(*args, **kwargs)
        ctx.verify_flags &= ~ssl.VERIFY_X509_STRICT
        return ctx

    ssl.create_default_context = _create_default_context
