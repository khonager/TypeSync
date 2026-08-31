import unittest
from unittest.mock import MagicMock, patch

try:
    from . import main
except ImportError:
    import main


class AccountDeletionTests(unittest.TestCase):
    def _query_with_documents(self, *documents):
        query = MagicMock()
        limited_query = query.limit.return_value
        limited_query.stream.side_effect = [list(documents), []]
        return query

    def _services(self, *, missing_auth_user=False):
        db = MagicMock()
        collections = {}

        for name in main.ACCOUNT_DATA_COLLECTIONS:
            collection = MagicMock()
            document = MagicMock()
            collection.where.return_value = self._query_with_documents(document)
            collections[name] = collection

        settings_document = MagicMock()
        nested_settings = self._query_with_documents(settings_document)
        user_ref = MagicMock()
        user_ref.collection.return_value = nested_settings
        user_ref.get.return_value.exists = True
        users = MagicMock()
        users.document.return_value = user_ref
        collections["users"] = users

        legacy_settings_ref = MagicMock()
        legacy_settings_ref.get.return_value.exists = True
        legacy_settings = MagicMock()
        legacy_settings.document.return_value = legacy_settings_ref
        collections["settings"] = legacy_settings

        db.collection.side_effect = lambda name: collections[name]

        firestore_service = MagicMock()
        firestore_service.client.return_value = db

        blobs = [MagicMock(), MagicMock()]
        bucket = MagicMock()
        bucket.list_blobs.return_value = blobs
        storage_service = MagicMock()
        storage_service.bucket.return_value = bucket

        class UserNotFoundError(Exception):
            pass

        auth_service = MagicMock()
        auth_service.UserNotFoundError = UserNotFoundError
        if missing_auth_user:
            auth_service.delete_user.side_effect = UserNotFoundError()

        return db, collections, user_ref, legacy_settings_ref, blobs, (
            firestore_service,
            storage_service,
            auth_service,
        )

    def test_deletes_all_user_resources_before_auth_user(self):
        (
            db,
            collections,
            user_ref,
            legacy_settings_ref,
            blobs,
            services,
        ) = self._services()
        firestore_service, storage_service, auth_service = services

        with (
            patch.object(main, "_firestore", return_value=firestore_service),
            patch.object(main, "_storage", return_value=storage_service),
            patch.object(main, "_auth", return_value=auth_service),
        ):
            result = main._delete_account_resources("user-123")

        self.assertEqual(result["deletedDocuments"], 9)
        self.assertEqual(result["deletedStorageObjects"], 2)
        for name in main.ACCOUNT_DATA_COLLECTIONS:
            collections[name].where.assert_called_once_with(
                "userId", "==", "user-123"
            )
        user_ref.collection.assert_called_once_with("settings")
        legacy_settings_ref.delete.assert_called_once_with()
        for blob in blobs:
            blob.delete.assert_called_once_with()
        user_ref.delete.assert_called_once_with()
        auth_service.delete_user.assert_called_once_with("user-123")
        self.assertEqual(db.batch.call_count, len(main.ACCOUNT_DATA_COLLECTIONS) + 1)

    def test_retry_is_successful_when_auth_user_is_already_missing(self):
        *_, services = self._services(missing_auth_user=True)
        firestore_service, storage_service, auth_service = services

        with (
            patch.object(main, "_firestore", return_value=firestore_service),
            patch.object(main, "_storage", return_value=storage_service),
            patch.object(main, "_auth", return_value=auth_service),
        ):
            result = main._delete_account_resources("user-123")

        self.assertEqual(result["deletedDocuments"], 9)
        self.assertEqual(result["deletedStorageObjects"], 2)


if __name__ == "__main__":
    unittest.main()
