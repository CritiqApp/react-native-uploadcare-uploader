package com.reactnativeuploadcareuploader;

import android.annotation.TargetApi;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;

import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.IOException;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

import okhttp3.FormBody;
import okhttp3.MultipartBody;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;

public class UploadcareUploaderService extends Service implements Runnable, UploadProgressListener {

    public static String NotificationName = "com.critiq.reactnativeuploadcareuploader";
    public static String StartEndpoint = "https://upload.uploadcare.com/multipart/start/";
    public static String CompleteEndpoint = "https://upload.uploadcare.com/multipart/complete/";
    public static String DirectEndpoint = "https://upload.uploadcare.com/base/";

    public static int ChunkSize = 5242880;
    public static int MaxDirectUpload = 10485760;
    public static int UploadUpdateInterval = 60;

    private NotificationManager mNotificationManager;
    private int notificationId;

    // Allow up to 5 chunks to be concurrently uploaded
    private ExecutorService executorService = Executors.newFixedThreadPool(5);
    private final OkHttpClient httpClient = new OkHttpClient();
    private HandlerThread handlerThread;
    private Handler handler;
    private Uri uri;
    private String key;
    private String sessionId;
    private int size;
    private String mimeType;
    private HashMap<String, String> metaData;
    private String uuid;
    private JSONArray parts;

    private long lastUpdate;
    private int totalUpload;
    private float progress;

    private boolean uploadError;

  /**
   * Handle uploading directly to Uploadcare (without multipart)
   */
  public void uploadDirect() throws IOException, JSONException {
        String name = this.sessionId;
        MultipartBody.Builder builder = new MultipartBody.Builder()
          .setType(MultipartBody.FORM)
          .addFormDataPart("UPLOADCARE_PUB_KEY", this.key)
          .addFormDataPart("UPLOADCARE_STORE", "auto")
          .addFormDataPart("filename", name);

        for (Map.Entry<String, String> entry: this.metaData.entrySet()) {
            if (entry.getValue() == null) {
                builder.addFormDataPart("metadata[" + entry.getKey() + "]", "");
            } else {
                builder.addFormDataPart("metadata[" + entry.getKey() + "]", entry.getValue());
            }
        }

        byte[] chunk = new byte[this.size];
        getFileStream().read(chunk);
        builder.addFormDataPart("file", name, new ChunkRequestBody(chunk, mimeType, this));

        Request request = new Request.Builder()
          .url(DirectEndpoint)
          .post(builder.build())
          .build();

        Response response = this.httpClient.newCall(request).execute();
        if (!response.isSuccessful()) throw new IOException("Unexpected code " + response);
        JSONObject json = new JSONObject(response.body().string());
        this.uuid = json.getString("file");
        notifyUUID();
        notifyDone();
  }

  /**
   * Start a multipart upload
   * @throws IOException
   * @throws Exception
   */
  public void startMultipart() throws IOException, JSONException {

        FormBody.Builder builder = new FormBody.Builder()
          .add("UPLOADCARE_PUB_KEY", this.key)
          .add("UPLOADCARE_STORE", "auto")
          .add("filename", this.sessionId)
          .add("size", size + "")
          .add("content_type", this.mimeType)
          .add("part_size", ChunkSize + "");

        for (Map.Entry<String, String> entry: this.metaData.entrySet()) {
            if (entry.getValue() == null) {
                builder.add("metadata[" + entry.getKey() + "]", "");
            } else {
                builder.add("metadata[" + entry.getKey() + "]", entry.getValue());
            }
        }
        Request request = new Request.Builder()
            .header("Content-Type", "multipart/form-data")
            .url(StartEndpoint)
            .post(builder.build())
            .build();

        Response response = httpClient.newCall(request).execute();
        if (!response.isSuccessful()) throw new IOException("Unexpected code " + response);
        JSONObject json = new JSONObject(response.body().string());
        this.uuid = json.getString("uuid");
        this.parts = json.getJSONArray("parts");
        notifyUUID();
    }

  /**
   * Upload a part of a multipart upload
   * @param index
   * @throws JSONException
   */
  private void uploadPart(int index) throws JSONException {
        final String part = parts.getString(index);
        final int length = ChunkSize * (index + 1) > size ? size % ChunkSize : ChunkSize;
        executorService.submit(new Runnable() {
            @Override
            public void run() {
                try {
                    // Read the data in
                    InputStream stream = UploadcareUploaderService.this.getFileStream();
                    stream.skip(index * ChunkSize);
                    byte[] chunk = new byte[length];
                    stream.read(chunk);
                    stream.close();

                    // Make the HTTP request
                    Request request = new Request.Builder()
                      .url(part)
                      .addHeader("Content-Type", "application/octet-stream")
                      .put(new ChunkRequestBody(chunk, "application/octet-stream", UploadcareUploaderService.this))
                      .build();

                    Response response = UploadcareUploaderService.this.httpClient.newCall(request).execute();
                    if (!response.isSuccessful()) throw new IOException("Unexpected code " + response);
                    System.out.println("Response (" + index + "): " + response.body().string());
                } catch (IOException e) {
                    uploadError = true;
                    executorService.shutdownNow();
                }
            }
        });
    }

    /**
     * Finish the multipart upload
     * @throws IOException
     */
    public void completeMultipart() throws IOException {
        FormBody.Builder builder = new FormBody.Builder()
          .add("UPLOADCARE_PUB_KEY", this.key)
          .add("uuid", this.uuid);
        Request request = new Request.Builder()
          .header("Content-Type", "multipart/form-data")
          .url(CompleteEndpoint)
          .post(builder.build())
          .build();
        Response response = UploadcareUploaderService.this.httpClient.newCall(request).execute();
        if (!response.isSuccessful()) throw new IOException("Unexpected code " + response);
    }

    /**
     * Notify the progress update back to the main application
     */
    public void notifyProgress() {
        Intent intent = new Intent("progress_update-" + sessionId);
        intent.putExtra("total", size);
        intent.putExtra("current", totalUpload);
        sendBroadcast(intent);
    }

    /**
     * Notify the uuid update back to the main application
     */
    public void notifyUUID() {
        Intent intent = new Intent("uuid_update-" + sessionId);
        intent.putExtra("uuid", uuid);
        sendBroadcast(intent);
    }

    public void notifyDone() {
        Intent intent = new Intent("done_update-" + sessionId);
        intent.putExtra("uuid", uuid);
        intent.putExtra("error", uploadError);
        sendBroadcast(intent);
    }

    public InputStream getFileStream() throws IOException {
        return this.getApplicationContext()
          .getContentResolver().openInputStream(uri);
    }

    @Override
    public void run() {
        try {
            if (size > MaxDirectUpload) {
                this.startMultipart();
                for (int i = 0; i < parts.length(); i++) {
                  this.uploadPart(i);
                }
                executorService.shutdown();
                executorService.awaitTermination(1, TimeUnit.HOURS);
                if (!this.uploadError) {
                    this.completeMultipart();
                }
            } else {
                this.uploadDirect();
            }
        } catch (Exception e) {
            e.printStackTrace();
            uploadError = true;
        }
        notifyDone();
        stopForeground(true);
        stopSelf();
    }

    @Override
    public synchronized void onProgress(int amount) {
        totalUpload += amount;
        if (lastUpdate < System.currentTimeMillis() - UploadUpdateInterval) {
            float lastProgress = progress;
            progress = totalUpload / (float)size;
            lastUpdate = System.currentTimeMillis();
            if ((int)(progress * 100) != (int)(lastProgress * 100)) {
                createNotification();
                notifyProgress();
            }
        }
    }

    @TargetApi(26)
    private NotificationChannel createNotificationChannel() {
        NotificationChannel mChannel = new NotificationChannel(NotificationName, NotificationName, NotificationManager.IMPORTANCE_LOW);
        mChannel.enableLights(true);
        mChannel.setLightColor(Color.BLUE);
        mChannel.setSound(null, null);
        mNotificationManager.createNotificationChannel(mChannel);
        return mChannel;
    }

    private Notification createNotification() {
        int roundedProgress = Math.round(progress * 100);
        NotificationCompat.Builder builder = new NotificationCompat.Builder(this, NotificationName)
          .setSmallIcon(android.R.drawable.ic_menu_upload)
          .setContentTitle("Uploading... (" + roundedProgress + "%)")
          .setOngoing(true)
          .setProgress(100, roundedProgress, false)
          .setPriority(NotificationCompat.PRIORITY_DEFAULT)
          .setSound(null);
        Notification notification = builder.build();
        mNotificationManager.notify(notificationId, notification);
        return notification;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        this.handlerThread = new HandlerThread("com.critiq.reactnativeuploadcarehandler");
        handlerThread.start();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
      notificationId = startId;
        mNotificationManager = (NotificationManager) this.getSystemService(Context.NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
          createNotificationChannel();
        }
        startForeground(notificationId, createNotification());

        String path = intent.getStringExtra("path");
        this.key = intent.getStringExtra("key");
        this.mimeType = intent.getStringExtra("type");
        this.metaData = (HashMap<String, String>) intent.getSerializableExtra("metaData");
        this.sessionId = intent.getStringExtra("sessionId");

        InputStream stream = null;
        try {
            this.uri = Uri.parse("file://" + path);
            stream = this.getFileStream();
            this.size = stream.available();

            this.handler = new Handler(handlerThread.getLooper());
            this.handler.post(this);

        } catch (Exception e) {
            e.printStackTrace();
            uploadError = true;
        }

        if (stream != null) {
            try {
                stream.close();
            } catch (IOException e) {}
        }
        return START_STICKY;
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
      return null;
    }

}
