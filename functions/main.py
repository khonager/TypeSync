# Welcome to Cloud Functions for Firebase for Python!
# To get started, simply uncomment the below code or create your own.
# Deploy with `firebase deploy`

from firebase_functions import https_fn
from firebase_functions.options import set_global_options
from firebase_functions.params import SecretParam
from firebase_admin import initialize_app
import requests
import os
import datetime
import base64
import json
import uuid
from urllib.parse import quote

# For cost control, you can set the maximum number of containers that can be
# running at the same time. This helps mitigate the impact of unexpected
# traffic spikes by instead downgrading performance. This limit is a per-function
# limit. You can override the limit for each function using the max_instances
# parameter in the decorator, e.g. @https_fn.on_request(max_instances=5).
set_global_options(max_instances=10)

initialize_app()


def _auth():
    from firebase_admin import auth

    return auth


def _firestore():
    from firebase_admin import firestore

    return firestore


def _storage():
    from firebase_admin import storage

    return storage

RESEND_API_URL = "https://api.resend.com/emails"
RESEND_FROM_EMAIL = "TypeSync <typesync@khonager.de>"
RESEND_API_KEY = SecretParam("RESEND_API_KEY")
REVENUECAT_WEBHOOK_AUTH_TOKEN = SecretParam("REVENUECAT_WEBHOOK_AUTH_TOKEN")

REVENUECAT_PLAN_BY_ENTITLEMENT = {
    "TypeSync Lite": {"tier": 1, "limit": 1 * 1024 * 1024 * 1024},
    "light": {"tier": 1, "limit": 1 * 1024 * 1024 * 1024},
    "plus": {"tier": 2, "limit": 25 * 1024 * 1024 * 1024},
    "pro": {"tier": 3, "limit": 100 * 1024 * 1024 * 1024},
}

REVENUECAT_PLAN_BY_PRODUCT = {
    "monthly": "TypeSync Lite",
    "typesync_light_monthly": "TypeSync Lite",
    "typesync_plus_monthly": "plus",
    "typesync_pro_monthly": "pro",
}

FREE_PLAN = {
    "plan_id": "free",
    "tier": 0,
    "limit": 5 * 1024 * 1024,
}

PLAN_LIMIT_BY_ID = {
    "free": FREE_PLAN["limit"],
    "TypeSync Lite": REVENUECAT_PLAN_BY_ENTITLEMENT["TypeSync Lite"]["limit"],
    "light": REVENUECAT_PLAN_BY_ENTITLEMENT["light"]["limit"],
    "plus": REVENUECAT_PLAN_BY_ENTITLEMENT["plus"]["limit"],
    "pro": REVENUECAT_PLAN_BY_ENTITLEMENT["pro"]["limit"],
}

PLAN_LIMIT_BY_TIER = {
    0: FREE_PLAN["limit"],
    1: REVENUECAT_PLAN_BY_ENTITLEMENT["TypeSync Lite"]["limit"],
    2: REVENUECAT_PLAN_BY_ENTITLEMENT["plus"]["limit"],
    3: REVENUECAT_PLAN_BY_ENTITLEMENT["pro"]["limit"],
}


def _int_value(value, fallback=0):
    try:
        return int(value)
    except (TypeError, ValueError):
        return fallback


def _storage_limit_from_user(user_data: dict) -> int:
    explicit_limit = _int_value(user_data.get("cloudStorageLimitBytes"), 0)
    if explicit_limit > 0:
        return explicit_limit

    plan_id = user_data.get("planId")
    if isinstance(plan_id, str) and plan_id in PLAN_LIMIT_BY_ID:
        return PLAN_LIMIT_BY_ID[plan_id]

    tier = _int_value(user_data.get("subscriptionTier"), FREE_PLAN["tier"])
    return PLAN_LIMIT_BY_TIER.get(tier, FREE_PLAN["limit"])


def _storage_usage_for_prefix(bucket, uid: str) -> tuple[int, int]:
    total_bytes = 0
    object_count = 0
    for blob in bucket.list_blobs(prefix=f"users/{uid}/"):
        total_bytes += int(blob.size or 0)
        object_count += 1
    return total_bytes, object_count


def _json_response(
    payload: dict,
    status: int = 200,
    *,
    cors: bool = False,
) -> https_fn.Response:
    headers = {"Content-Type": "application/json"}
    if cors:
        headers.update(
            {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "POST, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type, Authorization",
            }
        )
    return https_fn.Response(
        json.dumps(payload),
        status=status,
        headers=headers,
    )


def _handle_cors_preflight(req: https_fn.Request) -> https_fn.Response | None:
    if req.method == "OPTIONS":
        return _json_response({}, cors=True)
    return None


def _request_json(req: https_fn.Request) -> dict:
    payload = req.get_json(silent=True)
    if not isinstance(payload, dict):
        raise ValueError("Invalid JSON body")
    return payload


def _revenuecat_auth_valid(req: https_fn.Request) -> bool:
    expected = REVENUECAT_WEBHOOK_AUTH_TOKEN.value
    if not expected:
        print("Missing REVENUECAT_WEBHOOK_AUTH_TOKEN configuration")
        return False

    auth_header = req.headers.get("Authorization", "")
    bearer = f"Bearer {expected}"
    return auth_header == expected or auth_header == bearer


def _ms_to_iso(value) -> str | None:
    if value is None:
        return None
    try:
        milliseconds = int(value)
    except (TypeError, ValueError):
        return None
    return datetime.datetime.fromtimestamp(
        milliseconds / 1000,
        datetime.timezone.utc,
    ).isoformat()


def _first_string(value) -> str | None:
    if isinstance(value, str) and value:
        return value
    if isinstance(value, list):
        for item in value:
            if isinstance(item, str) and item:
                return item
    return None


def _plan_id_from_revenuecat_event(event: dict) -> str | None:
    entitlement_id = _first_string(
        event.get("entitlement_ids")
        or event.get("entitlement_id")
        or event.get("entitlementIds")
    )
    if entitlement_id in REVENUECAT_PLAN_BY_ENTITLEMENT:
        return entitlement_id

    product_id = _first_string(
        event.get("product_id")
        or event.get("product_identifier")
        or event.get("productIdentifier")
    )
    return REVENUECAT_PLAN_BY_PRODUCT.get(product_id)


def _revenuecat_status(event_type: str, period_type: str | None) -> str:
    if event_type == "EXPIRATION":
        return "expired"
    if event_type == "BILLING_ISSUE":
        return "past_due"
    if event_type == "CANCELLATION":
        return "canceled"
    if period_type == "TRIAL":
        return "trialing"
    return "active"


def _revenuecat_update_payload(event: dict) -> tuple[str, dict]:
    app_user_id = (
        event.get("app_user_id")
        or event.get("appUserId")
        or event.get("original_app_user_id")
    )
    if not isinstance(app_user_id, str) or not app_user_id:
        raise ValueError("Missing RevenueCat app user id")

    event_type = str(event.get("type") or event.get("event_type") or "").upper()
    period_type = event.get("period_type")
    if isinstance(period_type, str):
        period_type = period_type.upper()

    plan_id = _plan_id_from_revenuecat_event(event)
    if plan_id is None:
        raise ValueError("RevenueCat event does not match a TypeSync plan")
    if event_type == "EXPIRATION":
        plan_id = FREE_PLAN["plan_id"]

    plan = (
        FREE_PLAN
        if plan_id == FREE_PLAN["plan_id"]
        else REVENUECAT_PLAN_BY_ENTITLEMENT[plan_id]
    )
    status = _revenuecat_status(event_type, period_type)
    expiration = _ms_to_iso(
        event.get("expiration_at_ms") or event.get("expirationAtMs")
    )

    return app_user_id, {
        "subscriptionTier": plan["tier"],
        "planId": plan_id,
        "entitlementSource": "revenuecat",
        "subscriptionStatus": status,
        "subscriptionExpiresAt": expiration,
        "currentPeriodEnd": expiration,
        "cloudStorageLimitBytes": plan["limit"],
        "revenueCatEventType": event_type,
        "revenueCatProductId": _first_string(
            event.get("product_id")
            or event.get("product_identifier")
            or event.get("productIdentifier")
        ),
        "revenueCatEntitlementIds": event.get("entitlement_ids")
        or event.get("entitlementIds")
        or [],
        "updatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }


def _build_action_code_settings(data: dict) -> object:
    url = data.get("url")
    if not isinstance(url, str) or not url:
        raise ValueError("Missing action URL")

    kwargs = {
        "url": url,
        "handle_code_in_app": bool(data.get("handleCodeInApp", False)),
    }

    link_domain = data.get("linkDomain")
    if isinstance(link_domain, str) and link_domain:
        kwargs["link_domain"] = link_domain

    android_package_name = data.get("androidPackageName")
    if isinstance(android_package_name, str) and android_package_name:
        kwargs["android_package_name"] = android_package_name
        kwargs["android_install_app"] = bool(data.get("androidInstallApp", False))

    android_minimum_version = data.get("androidMinimumVersion")
    if isinstance(android_minimum_version, str) and android_minimum_version:
        kwargs["android_minimum_version"] = android_minimum_version

    ios_bundle_id = data.get("iOSBundleId")
    if isinstance(ios_bundle_id, str) and ios_bundle_id:
        kwargs["ios_bundle_id"] = ios_bundle_id

    return _auth().ActionCodeSettings(**kwargs)


def _resend_headers() -> dict[str, str]:
    api_key = RESEND_API_KEY.value
    if not api_key:
        raise RuntimeError("Missing RESEND_API_KEY configuration")
    return {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }


def _send_resend_email(
    *,
    to_email: str,
    subject: str,
    html_body: str,
    text_body: str,
) -> None:
    response = requests.post(
        RESEND_API_URL,
        headers=_resend_headers(),
        json={
            "from": RESEND_FROM_EMAIL,
            "to": [to_email],
            "subject": subject,
            "html": html_body,
            "text": text_body,
        },
        timeout=20,
    )

    if response.status_code < 200 or response.status_code >= 300:
        print(f"Resend send failed: {response.status_code} {response.text}")
        raise RuntimeError("Email delivery failed")


def _password_reset_email_content(email: str, action_link: str) -> tuple[str, str, str]:
    subject = "Reset your TypeSync password"
    html_body = f"""
    <div style="font-family: Arial, sans-serif; max-width: 560px; margin: 0 auto; color: #1f2937;">
      <h2 style="margin-bottom: 16px;">Reset your password</h2>
      <p style="line-height: 1.6;">We received a request to reset the TypeSync password for {email}.</p>
      <p style="line-height: 1.6;">Use the button below to choose a new password.</p>
      <p style="margin: 24px 0;">
        <a href="{action_link}" style="background: #111827; color: #ffffff; padding: 12px 20px; text-decoration: none; border-radius: 8px; display: inline-block;">
          Reset password
        </a>
      </p>
      <p style="line-height: 1.6;">If you did not request this, you can safely ignore this email.</p>
      <p style="font-size: 12px; color: #6b7280; line-height: 1.6;">If the button does not work, open this link manually:<br>{action_link}</p>
    </div>
    """.strip()
    text_body = (
        f"We received a request to reset the TypeSync password for {email}.\n\n"
        f"Reset your password here:\n{action_link}\n\n"
        "If you did not request this, you can ignore this email."
    )
    return subject, html_body, text_body


def _magic_link_email_content(action_link: str) -> tuple[str, str, str]:
    subject = "Your TypeSync sign-in link"
    html_body = f"""
    <div style="font-family: Arial, sans-serif; max-width: 560px; margin: 0 auto; color: #1f2937;">
      <h2 style="margin-bottom: 16px;">Sign in to TypeSync</h2>
      <p style="line-height: 1.6;">Use the secure link below to sign in to your TypeSync account.</p>
      <p style="margin: 24px 0;">
        <a href="{action_link}" style="background: #111827; color: #ffffff; padding: 12px 20px; text-decoration: none; border-radius: 8px; display: inline-block;">
          Sign in
        </a>
      </p>
      <p style="line-height: 1.6;">If you did not request this link, you can safely ignore this email.</p>
      <p style="font-size: 12px; color: #6b7280; line-height: 1.6;">If the button does not work, open this link manually:<br>{action_link}</p>
    </div>
    """.strip()
    text_body = (
        "Use this secure link to sign in to TypeSync:\n"
        f"{action_link}\n\n"
        "If you did not request this link, you can ignore this email."
    )
    return subject, html_body, text_body


def _verification_email_content(action_link: str) -> tuple[str, str, str]:
    subject = "Verify your TypeSync email"
    html_body = f"""
    <div style="font-family: Arial, sans-serif; max-width: 560px; margin: 0 auto; color: #1f2937;">
      <h2 style="margin-bottom: 16px;">Verify your email</h2>
      <p style="line-height: 1.6;">Confirm your email address to finish setting up TypeSync.</p>
      <p style="margin: 24px 0;">
        <a href="{action_link}" style="background: #111827; color: #ffffff; padding: 12px 20px; text-decoration: none; border-radius: 8px; display: inline-block;">
          Verify email
        </a>
      </p>
      <p style="line-height: 1.6;">If you did not create a TypeSync account, you can ignore this email.</p>
      <p style="font-size: 12px; color: #6b7280; line-height: 1.6;">If the button does not work, open this link manually:<br>{action_link}</p>
    </div>
    """.strip()
    text_body = (
        "Confirm your TypeSync email address here:\n"
        f"{action_link}\n\n"
        "If you did not create a TypeSync account, you can ignore this email."
    )
    return subject, html_body, text_body


def _send_password_reset_email_impl(data: dict) -> dict:
    email = (data.get("email") or "").strip()
    if not email:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Email is required."
        )

    settings = _build_action_code_settings(data)

    try:
        action_link = _auth().generate_password_reset_link(
            email,
            action_code_settings=settings,
        )
    except _auth().UserNotFoundError:
        return {"success": True}
    except _auth().InvalidRecipientEmailError:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Invalid email address."
        )
    except Exception as exc:
        print(f"Generate password reset link failed: {exc}")
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message="Failed to create password reset email."
        )

    subject, html_body, text_body = _password_reset_email_content(email, action_link)
    _send_resend_email(
        to_email=email,
        subject=subject,
        html_body=html_body,
        text_body=text_body,
    )
    return {"success": True}


def _send_magic_link_email_impl(data: dict) -> dict:
    email = (data.get("email") or "").strip()
    if not email:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Email is required."
        )

    settings = _build_action_code_settings(data)

    try:
        action_link = _auth().generate_sign_in_with_email_link(
            email,
            action_code_settings=settings,
        )
    except _auth().InvalidRecipientEmailError:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Invalid email address."
        )
    except Exception as exc:
        print(f"Generate sign-in link failed: {exc}")
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message="Failed to create sign-in email."
        )

    subject, html_body, text_body = _magic_link_email_content(action_link)
    _send_resend_email(
        to_email=email,
        subject=subject,
        html_body=html_body,
        text_body=text_body,
    )
    return {"success": True}


def _send_verification_email_impl(email: str, data: dict) -> dict:
    if not email:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Email is required."
        )

    settings = _build_action_code_settings(data)

    try:
        action_link = _auth().generate_email_verification_link(
            email,
            action_code_settings=settings,
        )
    except _auth().InvalidRecipientEmailError:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Invalid email address."
        )
    except Exception as exc:
        print(f"Generate verification link failed: {exc}")
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message="Failed to create verification email."
        )

    subject, html_body, text_body = _verification_email_content(action_link)
    _send_resend_email(
        to_email=email,
        subject=subject,
        html_body=html_body,
        text_body=text_body,
    )
    return {"success": True}


@https_fn.on_call(secrets=[RESEND_API_KEY])
def send_password_reset_email(req: https_fn.CallableRequest) -> dict:
    return _send_password_reset_email_impl(req.data or {})


@https_fn.on_request(secrets=[RESEND_API_KEY])
def send_password_reset_email_http(req: https_fn.Request) -> https_fn.Response:
    preflight = _handle_cors_preflight(req)
    if preflight is not None:
        return preflight
    if req.method != "POST":
        return _json_response({"error": "Method not allowed"}, status=405, cors=True)

    try:
        return _json_response(
            _send_password_reset_email_impl(_request_json(req)),
            cors=True,
        )
    except https_fn.HttpsError as exc:
        return _json_response({"error": exc.message}, status=400, cors=True)
    except Exception as exc:
        print(f"Password reset HTTP handler failed: {exc}")
        return _json_response({"error": "Failed to send password reset email."}, status=500, cors=True)


@https_fn.on_call(secrets=[RESEND_API_KEY])
def send_sign_in_link_email(req: https_fn.CallableRequest) -> dict:
    return _send_magic_link_email_impl(req.data or {})


@https_fn.on_request(secrets=[RESEND_API_KEY])
def send_sign_in_link_email_http(req: https_fn.Request) -> https_fn.Response:
    preflight = _handle_cors_preflight(req)
    if preflight is not None:
        return preflight
    if req.method != "POST":
        return _json_response({"error": "Method not allowed"}, status=405, cors=True)

    try:
        return _json_response(
            _send_magic_link_email_impl(_request_json(req)),
            cors=True,
        )
    except https_fn.HttpsError as exc:
        return _json_response({"error": exc.message}, status=400, cors=True)
    except Exception as exc:
        print(f"Magic link HTTP handler failed: {exc}")
        return _json_response({"error": "Failed to send sign-in email."}, status=500, cors=True)


@https_fn.on_call(secrets=[RESEND_API_KEY])
def send_verification_email(req: https_fn.CallableRequest) -> dict:
    if not req.auth or not req.auth.token.get("email"):
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="Authenticated user email is required."
        )
    return _send_verification_email_impl(req.auth.token.get("email"), req.data or {})


@https_fn.on_request(secrets=[RESEND_API_KEY])
def send_verification_email_http(req: https_fn.Request) -> https_fn.Response:
    preflight = _handle_cors_preflight(req)
    if preflight is not None:
        return preflight
    if req.method != "POST":
        return _json_response({"error": "Method not allowed"}, status=405, cors=True)

    try:
        uid = _verified_uid(req)
        user = _auth().get_user(uid)
        if not user.email:
            return _json_response({"error": "Authenticated user email is required."}, status=400, cors=True)
        return _json_response(
            _send_verification_email_impl(user.email, _request_json(req)),
            cors=True,
        )
    except https_fn.HttpsError as exc:
        status = 401 if exc.code == https_fn.FunctionsErrorCode.UNAUTHENTICATED else 400
        return _json_response({"error": exc.message}, status=status, cors=True)
    except Exception as exc:
        print(f"Verification email HTTP handler failed: {exc}")
        return _json_response({"error": "Failed to send verification email."}, status=500, cors=True)


def _bearer_token(req: https_fn.Request) -> str | None:
    auth_header = req.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        return None
    return auth_header[len("Bearer ") :].strip() or None


def _verified_uid(req: https_fn.Request) -> str:
    token = _bearer_token(req)
    if not token:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="Missing bearer token."
        )

    try:
        decoded = _auth().verify_id_token(token)
    except Exception as exc:
        print(f"Auth verification failed: {exc}")
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="Invalid auth token."
        )

    uid = decoded.get("uid")
    if not uid:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="Authenticated user missing uid."
        )
    return uid


@https_fn.on_request()
def upload_storage_object(req: https_fn.Request) -> https_fn.Response:
    if req.method != "POST":
        return https_fn.Response("Method not allowed", status=405)

    uid = _verified_uid(req)

    try:
        payload = req.get_json(silent=True) or {}
        target_uid = payload.get("userId")
        destination_path = payload.get("destinationPath")
        data_b64 = payload.get("dataBase64")
        content_type = payload.get("contentType") or "application/octet-stream"
    except Exception as exc:
        print(f"Bad upload payload: {exc}")
        return https_fn.Response(
            json.dumps({"error": "Invalid JSON body"}),
            status=400,
            content_type="application/json",
        )

    if target_uid != uid:
        return https_fn.Response(
            json.dumps({"error": "userId does not match authenticated user"}),
            status=403,
            content_type="application/json",
        )

    if not destination_path or not data_b64:
        return https_fn.Response(
            json.dumps({"error": "destinationPath and dataBase64 are required"}),
            status=400,
            content_type="application/json",
        )

    object_path = f"users/{uid}/{destination_path}"

    try:
        file_bytes = base64.b64decode(data_b64)
    except Exception as exc:
        print(f"Base64 decode failed: {exc}")
        return https_fn.Response(
            json.dumps({"error": "Invalid base64 payload"}),
            status=400,
            content_type="application/json",
        )

    download_token = str(uuid.uuid4())
    bucket = _storage().bucket()
    blob = bucket.blob(object_path)

    try:
        existing_size = 0
        if blob.exists():
            blob.reload()
            existing_size = int(blob.size or 0)
    except Exception as exc:
        print(f"Existing object lookup failed: {exc}")
        return https_fn.Response(
            json.dumps({"error": f"Could not inspect existing object: {exc}"}),
            status=500,
            content_type="application/json",
        )

    upload_size = len(file_bytes)
    quota_delta = max(upload_size - existing_size, 0)
    db = _firestore().client()
    firestore_module = _firestore()
    user_ref = db.collection("users").document(uid)
    user_snapshot = user_ref.get()
    user_data = user_snapshot.to_dict() or {}
    baseline_usage = None
    if not user_snapshot.exists or "storageUsedBytes" not in user_data:
        baseline_usage, _ = _storage_usage_for_prefix(bucket, uid)
    transaction = db.transaction()

    @firestore_module.transactional
    def reserve_storage(transaction):
        snapshot = user_ref.get(transaction=transaction)
        user_data = snapshot.to_dict() or {}
        current_usage = _int_value(
            user_data.get("storageUsedBytes"),
            baseline_usage or 0,
        )
        storage_limit = _storage_limit_from_user(user_data)
        next_usage = current_usage + quota_delta
        if next_usage > storage_limit:
            raise ValueError(
                json.dumps(
                    {
                        "code": "quota-exceeded",
                        "usedBytes": current_usage,
                        "requestedBytes": upload_size,
                        "limitBytes": storage_limit,
                    }
                )
            )
        if quota_delta > 0 or baseline_usage is not None:
            transaction.set(
                user_ref,
                {"storageUsedBytes": next_usage},
                merge=True,
            )
        return next_usage, storage_limit

    try:
        storage_used_bytes, storage_limit_bytes = reserve_storage(transaction)
    except ValueError as exc:
        try:
            payload = json.loads(str(exc))
        except Exception:
            payload = {"error": str(exc)}
        return https_fn.Response(
            json.dumps(payload),
            status=403,
            content_type="application/json",
        )

    try:
        blob.metadata = {"firebaseStorageDownloadTokens": download_token}
        blob.upload_from_string(file_bytes, content_type=content_type)

        bucket_name = bucket.name
        download_url = (
            f"https://firebasestorage.googleapis.com/v0/b/{bucket_name}/o/"
            f"{quote(object_path, safe='')}?alt=media&token={download_token}"
        )

        return https_fn.Response(
            json.dumps(
                {
                    "downloadUrl": download_url,
                    "size": len(file_bytes),
                    "bucket": bucket_name,
                    "path": object_path,
                    "storageUsedBytes": storage_used_bytes,
                    "storageLimitBytes": storage_limit_bytes,
                }
            ),
            status=200,
            content_type="application/json",
        )
    except Exception as exc:
        if quota_delta > 0:
            try:
                user_ref.update(
                    {"storageUsedBytes": max(storage_used_bytes - quota_delta, 0)}
                )
            except Exception as rollback_exc:
                print(f"Storage usage rollback failed: {rollback_exc}")
        print(f"Storage upload failed: {exc}")
        return https_fn.Response(
            json.dumps({"error": f"Upload failed: {exc}"}),
            status=500,
            content_type="application/json",
        )


@https_fn.on_request()
def delete_storage_object(req: https_fn.Request) -> https_fn.Response:
    if req.method != "POST":
        return https_fn.Response("Method not allowed", status=405)

    uid = _verified_uid(req)

    try:
        payload = req.get_json(silent=True) or {}
        target_uid = payload.get("userId")
        object_path = payload.get("objectPath")
    except Exception as exc:
        print(f"Bad delete payload: {exc}")
        return https_fn.Response(
            json.dumps({"error": "Invalid JSON body"}),
            status=400,
            content_type="application/json",
        )

    if target_uid != uid:
        return https_fn.Response(
            json.dumps({"error": "userId does not match authenticated user"}),
            status=403,
            content_type="application/json",
        )

    if not object_path or not isinstance(object_path, str):
        return https_fn.Response(
            json.dumps({"error": "objectPath is required"}),
            status=400,
            content_type="application/json",
        )

    expected_prefix = f"users/{uid}/"
    if not object_path.startswith(expected_prefix):
        return https_fn.Response(
            json.dumps(
                {"error": "objectPath is outside the authenticated user scope"}
            ),
            status=403,
            content_type="application/json",
        )

    try:
        bucket = _storage().bucket()
        blob = bucket.blob(object_path)
        if not blob.exists():
            return https_fn.Response(
                json.dumps({"error": "Object not found"}),
                status=404,
                content_type="application/json",
            )

        blob.reload()
        size = int(blob.size or 0)
        blob.delete()
        db = _firestore().client()
        user_ref = db.collection("users").document(uid)
        user_snapshot = user_ref.get()
        user_data = user_snapshot.to_dict() or {}
        current_usage = _int_value(user_data.get("storageUsedBytes"), 0)
        storage_used_bytes = max(current_usage - size, 0)
        user_ref.set({"storageUsedBytes": storage_used_bytes}, merge=True)

        return https_fn.Response(
            json.dumps(
                {
                    "deleted": True,
                    "size": size,
                    "bucket": bucket.name,
                    "path": object_path,
                    "storageUsedBytes": storage_used_bytes,
                }
            ),
            status=200,
            content_type="application/json",
        )
    except Exception as exc:
        print(f"Delete storage object failed: {exc}")
        return https_fn.Response(
            json.dumps({"error": f"Delete failed: {exc}"}),
            status=500,
            content_type="application/json",
        )


@https_fn.on_request()
def audit_storage_usage(req: https_fn.Request) -> https_fn.Response:
    if req.method != "POST":
        return https_fn.Response("Method not allowed", status=405)

    uid = _verified_uid(req)

    try:
        payload = req.get_json(silent=True) or {}
        target_uid = payload.get("userId")
    except Exception as exc:
        print(f"Bad audit payload: {exc}")
        return https_fn.Response(
            json.dumps({"error": "Invalid JSON body"}),
            status=400,
            content_type="application/json",
        )

    if target_uid != uid:
        return https_fn.Response(
            json.dumps({"error": "userId does not match authenticated user"}),
            status=403,
            content_type="application/json",
        )

    try:
        bucket = _storage().bucket()
        total_bytes, object_count = _storage_usage_for_prefix(bucket, uid)

        _firestore().client().collection("users").document(uid).set(
            {"storageUsedBytes": total_bytes},
            merge=True,
        )

        return https_fn.Response(
            json.dumps(
                {
                    "storageUsedBytes": total_bytes,
                    "storedFileBytes": total_bytes,
                    "storedFileCount": object_count,
                }
            ),
            status=200,
            content_type="application/json",
        )
    except Exception as exc:
        print(f"Storage audit failed: {exc}")
        return https_fn.Response(
            json.dumps({"error": f"Audit failed: {exc}"}),
            status=500,
            content_type="application/json",
        )


@https_fn.on_request(secrets=[REVENUECAT_WEBHOOK_AUTH_TOKEN])
def revenuecat_webhook(req: https_fn.Request) -> https_fn.Response:
    if req.method != "POST":
        return _json_response({"error": "Method not allowed"}, status=405)

    if not _revenuecat_auth_valid(req):
        return _json_response({"error": "Unauthorized"}, status=401)

    try:
        payload = _request_json(req)
        event = payload.get("event", payload)
        if not isinstance(event, dict):
            raise ValueError("Missing RevenueCat event payload")

        uid, updates = _revenuecat_update_payload(event)
        _firestore().client().collection("users").document(uid).set(
            updates,
            merge=True,
        )
        return _json_response({"success": True, "userId": uid})
    except ValueError as exc:
        return _json_response({"error": str(exc)}, status=400)
    except Exception as exc:
        print(f"RevenueCat webhook failed: {exc}")
        return _json_response(
            {"error": "Failed to process RevenueCat webhook."},
            status=500,
        )


@https_fn.on_call()
def verify_gumroad_license(req: https_fn.CallableRequest) -> dict:
    """Verifies a Gumroad license key and updates the user's subscription."""
    # 1. Authenticate user
    if not req.auth:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="The function must be called while authenticated."
        )

    uid = req.auth.uid
    license_key = req.data.get("license_key")
    product_permalink = req.data.get("product_permalink")  # Optional override

    if not license_key:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="The function must be called with a 'license_key' argument."
        )

    # 2. Call Gumroad API
    # You generally need the PRODUCT_ID or PERMALINK. 
    # For verification, knowing the Product Permalink is usually enough if checking against a specific product.
    # Ideally, store PRODUCT_ID in environment variables.
    
    # We'll use the specific product permalink provided.
    target_product_permalink = product_permalink or "ixufbj"

    try:
        response = requests.post(
            "https://api.gumroad.com/v2/licenses/verify",
            data={
                "product_permalink": target_product_permalink,
                "license_key": license_key,
                "increment_uses_count": "true"
            }
        )
        data = response.json()
    except Exception as e:
        print(f"Error calling Gumroad: {e}")
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message="Failed to verify license with Gumroad."
        )

    # 3. Validate response
    if not data.get("success"):
        return {"success": False, "message": "Invalid license key."}

    purchase = data.get("purchase", {})
    if purchase.get("refunded"):
        return {"success": False, "message": "This license has been refunded."}

    if purchase.get("chargebacked"):
        return {"success": False, "message": "This license has been chargebacked."}
    
    # 4. Update Firestore
    tier_to_grant = "premium" 
    
    try:
        db = _firestore().client()
        user_ref = db.collection("users").document(uid)
        
        user_ref.set({
            "subscriptionTier": 3, # Assuming Premium is index 3.
            "subscriptionSource": "gumroad",
            "gumroadLicenseKey": license_key,
            "updatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat()
        }, merge=True)
        
    except Exception as e:
        print(f"Error updating Firestore: {e}")
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message="Failed to update user subscription."
        )

    return {
        "success": True, 
        "message": "License verified! Premium features unlocked.",
        "tier": tier_to_grant
    }

@https_fn.on_call()
def check_patreon_subscription(req: https_fn.CallableRequest) -> dict:
    """Checks Patreon membership by email and updates subscription."""
    if not req.auth:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="The function must be called while authenticated."
        )

    uid = req.auth.uid
    email = req.auth.token.get("email")
    if not email:
         raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.FAILED_PRECONDITION,
            message="User must have an email address."
        )

    # SECRETS (Should be in env vars)
    access_token = os.environ.get("PATREON_ACCESS_TOKEN")
    campaign_id = os.environ.get("PATREON_CAMPAIGN_ID")
    
    if not access_token or not campaign_id:
        print("Missing Patreon configuration")
        return {
            "success": False, 
            "message": "Server configuration error (Missing Patreon keys)."
        }

    # 1. Fetch Members from Patreon
    headers = {
        "Authorization": f"Bearer {access_token}"
    }
    
    found_tier = None
    
    try:
        # Requesting fields: email, entitled_tiers
        url = f"https://www.patreon.com/api/oauth2/v2/campaigns/{campaign_id}/members"
        params = {
            "include": "currently_entitled_tiers",
            "fields[member]": "email,full_name,patron_status",
            "fields[tier]": "title,id",
            "page[size]": 100 
        }
        
        response = requests.get(url, headers=headers, params=params)
        json_resp = response.json()
        
        data_list = json_resp.get("data", [])
        included = json_resp.get("included", [])
        
        # Helper to map Tier ID to Title
        tiers_by_id = {item["id"]: item["attributes"]["title"] for item in included if item["type"] == "tier"}

        # Find user
        for member in data_list:
            attrs = member.get("attributes", {})
            if attrs.get("email") and attrs.get("email").lower() == email.lower():
                # Check active status
                if attrs.get("patron_status") != "active_patron":
                    return {"success": False, "message": "Patreon membership is not active."}
                
                # Check tiers
                relationships = member.get("relationships", {})
                entitled = relationships.get("currently_entitled_tiers", {}).get("data", [])
                
                for t in entitled:
                    tier_id = t.get("id")
                    tier_title = tiers_by_id.get(tier_id, "")
                    
                    if tier_title:
                        found_tier = tier_title
                        break
                break
                
    except Exception as e:
        print(f"Patreon API Error: {e}")
        return {"success": False, "message": "Failed to verify with Patreon."}

    if not found_tier:
        return {"success": False, "message": "No active TypeSync subscription found on Patreon for this email."}

    # 2. Update Firestore
    try:
        db = _firestore().client()
        user_ref = db.collection("users").document(uid)
        
        user_ref.set({
            "subscriptionTier": 3, # Grant Premium
            "subscriptionSource": "patreon",
            "patreonTierName": found_tier,
            "updatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat()
        }, merge=True)
        
    except Exception as e:
        print(f"Error updating Firestore: {e}")
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message="Failed to update user subscription."
        )

    return {
        "success": True, 
        "message": f"Verified Patreon tier: {found_tier}. Premium unlocked!",
        "tier": "premium"
    }
