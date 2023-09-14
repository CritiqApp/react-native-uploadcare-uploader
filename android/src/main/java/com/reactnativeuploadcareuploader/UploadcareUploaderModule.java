package com.reactnativeuploadcareuploader;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;

import androidx.annotation.NonNull;
import androidx.lifecycle.LiveData;

import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.ReadableMapKeySetIterator;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.module.annotations.ReactModule;
import com.facebook.react.modules.core.DeviceEventManagerModule;

import java.util.HashMap;
import java.util.UUID;

@ReactModule(name = UploadcareUploaderModule.NAME)
public class UploadcareUploaderModule extends ReactContextBaseJavaModule {
    public static final String NAME = "UploadcareUploader";

    public UploadcareUploaderModule(ReactApplicationContext reactContext) {
        super(reactContext);
    }

    @Override
    @NonNull
    public String getName() {
        return NAME;
    }


    // Example method
    // See https://reactnative.dev/docs/native-modules-android
    @ReactMethod
    public void upload(String key, String path, String type, ReadableMap data, Promise promise) {

        HashMap<String, String> metaData = new HashMap<String, String>();
        ReadableMapKeySetIterator iterator = data.keySetIterator();
        while(iterator.hasNextKey()) {
            String k = iterator.nextKey();
            metaData.put(k, data.getString(key));
        }

        String sessionId = UUID.randomUUID().toString();
        Intent serviceIntent = new Intent(getReactApplicationContext(), UploadcareUploaderService.class);
        serviceIntent.putExtra("key", key);
        serviceIntent.putExtra("path", path);
        serviceIntent.putExtra("type", type);
        serviceIntent.putExtra("metaData", metaData);
        serviceIntent.putExtra("sessionId", sessionId);
        getReactApplicationContext().startService(serviceIntent);

        // Notify JS of the new upload session
        getReactApplicationContext()
          .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class)
          .emit("new_upload_session", sessionId);

        BroadcastReceiver progressReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                WritableMap payload = Arguments.createMap();
                payload.putInt("total", intent.getIntExtra("total", 0));
                payload.putInt("current", intent.getIntExtra("current", 0));
                payload.putString("session_id", sessionId);
                getReactApplicationContext()
                  .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class)
                  .emit("upload_session_progress", payload);
            }
        };
        getReactApplicationContext().registerReceiver(
          progressReceiver,
          new IntentFilter("progress_update-" + sessionId)
        );

        BroadcastReceiver uuidReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                WritableMap payload = Arguments.createMap();
                payload.putString("uuid", intent.getStringExtra("uuid"));
                payload.putString("session_id", sessionId);
                getReactApplicationContext()
                  .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class)
                  .emit("media_uuid_created", payload);
            }
        };
        getReactApplicationContext().registerReceiver(
          uuidReceiver,
          new IntentFilter("uuid_update-" + sessionId)
        );

        BroadcastReceiver doneReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                String uuid = intent.getStringExtra("uuid");
                boolean error = intent.getBooleanExtra("error", true);
                if (error) {
                    promise.reject("UploadError", "error");
                } else {
                    promise.resolve(uuid);
                }
            }
        };
        getReactApplicationContext().registerReceiver(
          doneReceiver,
          new IntentFilter("done_update-" + sessionId)
        );

    }


}
