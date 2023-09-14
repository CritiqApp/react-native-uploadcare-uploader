package com.reactnativeuploadcareuploader;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;

import okhttp3.MediaType;
import okhttp3.RequestBody;
import okio.BufferedSink;

public class ChunkRequestBody extends RequestBody {

    private byte[] chunk;
    private UploadProgressListener listener;
    private String type;

    public ChunkRequestBody(byte[] chunk, String type, UploadProgressListener listener) {
        this.chunk = chunk;
        this.type = type;
        this.listener = listener;
    }

    @Override
    public void writeTo(@NonNull BufferedSink bufferedSink) throws IOException {
        ByteBuffer buffer = ByteBuffer.wrap(chunk);
        while (buffer.hasRemaining()) {
            int size = Math.min(buffer.remaining(), 2048);
            byte[] send = new byte[size];
            buffer.get(send);
            bufferedSink.write(send);
            this.listener.onProgress(size);
        }
    }

    @Nullable
    @Override
    public MediaType contentType() {
        return MediaType.parse(type);
    }

    @Override
    public long contentLength() throws IOException {
        return chunk.length;
    }
}
