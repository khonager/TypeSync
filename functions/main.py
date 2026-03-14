# Welcome to Cloud Functions for Firebase for Python!
# To get started, simply uncomment the below code or create your own.
# Deploy with `firebase deploy`

from firebase_functions import https_fn
from firebase_functions.options import set_global_options
from firebase_admin import initialize_app, firestore, auth, storage
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
        decoded = auth.verify_id_token(token)
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

    try:
        bucket = storage.bucket()
        blob = bucket.blob(object_path)
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
                }
            ),
            status=200,
            content_type="application/json",
        )
    except Exception as exc:
        print(f"Storage upload failed: {exc}")
        return https_fn.Response(
            json.dumps({"error": f"Upload failed: {exc}"}),
            status=500,
            content_type="application/json",
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
        db = firestore.client()
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
        db = firestore.client()
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
