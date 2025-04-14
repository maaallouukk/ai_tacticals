package com.example.analysis_ai;

import android.content.ContentValues;
import android.content.Context;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.BinaryMessenger;
import java.io.File;
import java.io.FileInputStream;
import java.io.OutputStream;
import android.util.Log;

public class GallerySaverPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private static final String CHANNEL = "com.example.analysis_ai/gallery_saver";
    private static final String TAG = "GallerySaverPlugin";
    private Context context;
    private MethodChannel channel;

    // Called by FlutterPlugin
    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
        Log.d(TAG, "GallerySaverPlugin attached to engine");
    }

    // For manual registration in MainActivity
    public void onAttachedToEngine(BinaryMessenger messenger, Context ctx) {
        context = ctx;
        channel = new MethodChannel(messenger, CHANNEL);
        channel.setMethodCallHandler(this);
        Log.d(TAG, "GallerySaverPlugin manually attached to engine");
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (call.method.equals("saveVideo")) {
            String path = call.argument("path");
            String albumName = call.argument("albumName");
            boolean toDcim = call.argument("toDcim");

            try {
                Log.d(TAG, "Attempting to save video: path=" + path + ", album=" + albumName + ", toDcim=" + toDcim);
                Uri uri = saveVideoToGallery(path, albumName, toDcim);
                result.success(uri != null);
                Log.d(TAG, "Video save result: " + (uri != null));
            } catch (Exception e) {
                Log.e(TAG, "Failed to save video: " + e.getMessage());
                result.error("SAVE_VIDEO_ERROR", "Failed to save video: " + e.getMessage(), null);
            }
        } else {
            Log.w(TAG, "Method not implemented: " + call.method);
            result.notImplemented();
        }
    }

    private Uri saveVideoToGallery(String filePath, String albumName, boolean toDcim) throws Exception {
        File file = new File(filePath);
        if (!file.exists()) {
            Log.e(TAG, "File does not exist: " + filePath);
            throw new Exception("File does not exist: " + filePath);
        }
        Log.d(TAG, "Saving video: " + filePath + ", size: " + file.length());

        ContentValues values = new ContentValues();
        values.put(MediaStore.Video.Media.DISPLAY_NAME, file.getName());
        values.put(MediaStore.Video.Media.MIME_TYPE, "video/mp4");
        values.put(MediaStore.Video.Media.DATE_ADDED, System.currentTimeMillis() / 1000);
        values.put(MediaStore.Video.Media.DATE_TAKEN, System.currentTimeMillis());

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            String relativePath = toDcim ? Environment.DIRECTORY_DCIM : Environment.DIRECTORY_MOVIES + "/" + albumName;
            values.put(MediaStore.Video.Media.RELATIVE_PATH, relativePath);
            values.put(MediaStore.Video.Media.IS_PENDING, 1);
            Log.d(TAG, "Saving to relative path: " + relativePath);
        } else {
            String directory = toDcim ? Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM).getPath()
                    : Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES).getPath() + "/" + albumName;
            File dir = new File(directory);
            if (!dir.exists()) {
                dir.mkdirs();
                Log.d(TAG, "Created directory: " + directory);
            }
            File destFile = new File(dir, file.getName());
            file.renameTo(destFile);
            values.put(MediaStore.Video.Media.DATA, destFile.getAbsolutePath());
            Log.d(TAG, "Saving to legacy path: " + destFile.getAbsolutePath());
        }

        Uri uri = context.getContentResolver().insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values);
        if (uri == null) {
            Log.e(TAG, "Failed to create MediaStore entry");
            throw new Exception("Failed to create MediaStore entry");
        }

        try {
            OutputStream out = context.getContentResolver().openOutputStream(uri);
            FileInputStream in = new FileInputStream(file);
            byte[] buffer = new byte[1024];
            int len;
            while ((len = in.read(buffer)) > 0) {
                out.write(buffer, 0, len);
            }
            out.close();
            in.close();
            Log.d(TAG, "File written to MediaStore");

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                values.clear();
                values.put(MediaStore.Video.Media.IS_PENDING, 0);
                context.getContentResolver().update(uri, values, null, null);
                Log.d(TAG, "MediaStore entry updated, IS_PENDING set to 0");
            }
            return uri;
        } catch (Exception e) {
            Log.e(TAG, "Error writing to MediaStore: " + e.getMessage());
            context.getContentResolver().delete(uri, null, null);
            throw e;
        }
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (channel != null) {
            channel.setMethodCallHandler(null);
            channel = null;
        }
        context = null;
        Log.d(TAG, "GallerySaverPlugin detached from engine");
    }
}