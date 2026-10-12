package com.prismapi.prisma_mobile_spike

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * M0-only proof that opaque appliance credentials can be protected by an
 * Android Keystore key instead of being stored as plaintext app metadata.
 *
 * Ciphertext is kept in private SharedPreferences; the AES key itself remains
 * in AndroidKeyStore and is never exported. This is diagnostic infrastructure,
 * not the final production plugin/API surface.
 */
class KeystoreSecretBridge(context: Context) {
    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun runProbe(): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return mapOf(
                "supported" to false,
                "reason" to "Android Keystore AES/GCM probe requires API 23+",
            )
        }

        val credentialId = "m0-probe"
        val original = ByteArray(32).also { SecureRandom().nextBytes(it) }
        return try {
            writeSecret(credentialId, original)
            val recovered = readSecret(credentialId)
            val ok = recovered != null && MessageDigest.isEqual(original, recovered)
            deleteSecret(credentialId)
            mapOf(
                "supported" to true,
                "round_trip" to ok,
                "key_provider" to "AndroidKeyStore",
                "cipher" to TRANSFORMATION,
                "plaintext_persisted" to false,
            )
        } finally {
            original.fill(0)
        }
    }

    fun writeSecret(credentialId: String, secret: ByteArray) {
        require(credentialId.isNotBlank()) { "credentialId is required" }
        require(Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) { "API 23+ required" }

        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateMasterKey())
        val ciphertext = cipher.doFinal(secret)
        val iv = cipher.iv

        val encoded = Base64.encodeToString(iv, Base64.NO_WRAP) + ":" +
            Base64.encodeToString(ciphertext, Base64.NO_WRAP)
        prefs.edit().putString(storageKey(credentialId), encoded).apply()
    }

    fun readSecret(credentialId: String): ByteArray? {
        require(credentialId.isNotBlank()) { "credentialId is required" }
        require(Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) { "API 23+ required" }

        val encoded = prefs.getString(storageKey(credentialId), null) ?: return null
        val parts = encoded.split(':', limit = 2)
        require(parts.size == 2) { "Malformed protected secret" }

        val iv = Base64.decode(parts[0], Base64.NO_WRAP)
        val ciphertext = Base64.decode(parts[1], Base64.NO_WRAP)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            getOrCreateMasterKey(),
            GCMParameterSpec(GCM_TAG_BITS, iv),
        )
        return cipher.doFinal(ciphertext)
    }

    fun deleteSecret(credentialId: String) {
        prefs.edit().remove(storageKey(credentialId)).apply()
    }

    private fun storageKey(credentialId: String): String = "credential:$credentialId"

    private fun getOrCreateMasterKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getKey(MASTER_KEY_ALIAS, null) as? SecretKey)?.let { return it }

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            ANDROID_KEYSTORE,
        )
        keyGenerator.init(
            KeyGenParameterSpec.Builder(
                MASTER_KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return keyGenerator.generateKey()
    }

    companion object {
        private const val PREFS_NAME = "prisma_m0_secure_store"
        private const val MASTER_KEY_ALIAS = "prisma.pi.appliance.credentials.m0"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_TAG_BITS = 128
    }
}
