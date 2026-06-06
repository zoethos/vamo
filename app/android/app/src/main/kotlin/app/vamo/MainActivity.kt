package app.vamo

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.ContactsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private var pickMode: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickPhone" -> launchPick(PHONE, result)
                "pickEmail" -> launchPick(EMAIL, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun launchPick(mode: String, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("busy", "Picker already active", null)
            return
        }
        pendingResult = result
        pickMode = mode
        val contentType = when (mode) {
            PHONE -> ContactsContract.CommonDataKinds.Phone.CONTENT_TYPE
            EMAIL -> ContactsContract.CommonDataKinds.Email.CONTENT_TYPE
            else -> {
                clearPending()
                result.error("invalid_mode", "Unknown pick mode", null)
                return
            }
        }
        val intent = Intent(Intent.ACTION_PICK).apply { type = contentType }
        try {
            startActivityForResult(intent, PICK_REQUEST)
        } catch (error: Exception) {
            clearPending()
            result.error("picker_unavailable", error.message, null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == PICK_REQUEST) {
            val result = pendingResult
            val mode = pickMode
            clearPending()
            if (result == null) {
                super.onActivityResult(requestCode, resultCode, data)
                return
            }
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                result.success(null)
                return
            }
            try {
                result.success(readContactData(data.data!!, mode))
            } catch (error: Exception) {
                result.error("picker_read_failed", error.message, null)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun clearPending() {
        pendingResult = null
        pickMode = null
    }

    private fun readContactData(uri: Uri, mode: String?): Map<String, String?>? {
        val projection = when (mode) {
            PHONE -> arrayOf(
                ContactsContract.CommonDataKinds.Phone.NUMBER,
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
            )
            EMAIL -> arrayOf(
                ContactsContract.CommonDataKinds.Email.ADDRESS,
                ContactsContract.CommonDataKinds.Email.DISPLAY_NAME,
            )
            else -> return null
        }
        contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            val value = cursor.getString(0)?.trim().orEmpty()
            if (value.isEmpty()) return null
            val label = cursor.getString(1)?.trim().orEmpty()
            return mapOf(
                "value" to value,
                "displayLabel" to if (label.isEmpty()) null else label,
            )
        }
        return null
    }

    companion object {
        private const val CHANNEL_NAME = "app.vamo/contact_invite"
        private const val PICK_REQUEST = 99126
        private const val PHONE = "phone"
        private const val EMAIL = "email"
    }
}
