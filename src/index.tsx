import {
  NativeEventEmitter,
  DeviceEventEmitter,
  NativeModules,
  Platform,
} from 'react-native';

const LINKING_ERROR =
  `The package 'react-native-uploadcare-uploader' doesn't seem to be linked. Make sure: \n\n` +
  Platform.select({ ios: "- You have run 'pod install'\n", default: '' }) +
  '- You rebuilt the app after installing the package\n' +
  '- You are not using Expo managed workflow\n';

const UploadcareUploader = NativeModules.UploadcareUploader
  ? NativeModules.UploadcareUploader
  : new Proxy(
      {},
      {
        get() {
          throw new Error(LINKING_ERROR);
        },
      }
    );

// Define the emitter
const emitter =
  Platform.OS === 'ios'
    ? new NativeEventEmitter(NativeModules.UploadcareUploader)
    : DeviceEventEmitter;

type ProgressCallback = (current: number, total: number) => void;
type UUIDCreateCallback = (uuid: string) => void;

// Tracks the upload id
var id = 1;

// Queue up upload session IDs
const progressCallbackQueue: number[] = [];

// Map callback ID to callback
const callbackRegistry: {
  [id: number]: {
    onProgress: ProgressCallback | undefined;
    onUUIDCreated: UUIDCreateCallback | undefined;
  };
} = {};
// Map session ID to callback ID
const sessionToId: { [key: string]: number } = {};
const idToSession: { [key: number]: string } = {};

// Add the callback to the registry
function addCallbacks(callbacks: {
  onProgress: ProgressCallback | undefined;
  onUUIDCreated: UUIDCreateCallback | undefined;
}) {
  const callbackId = id;
  progressCallbackQueue.push(callbackId);
  callbackRegistry[callbackId] = callbacks;
  id += 1;
  return () => removeCallback(callbackId);
}

function removeCallback(callbackId: number) {
  const sessionId = idToSession[callbackId];
  delete idToSession[callbackId];
  delete sessionToId[sessionId];
  delete callbackRegistry[callbackId];
}

// Register a new upload session
emitter.addListener('new_upload_session', (sessionId: string) => {
  const callbackId = progressCallbackQueue.pop();
  if (callbackId) {
    sessionToId[sessionId] = callbackId;
    idToSession[callbackId] = sessionId;
  }
});

// Process an upload progress
emitter.addListener(
  'upload_session_progress',
  (data: { session_id: string; current: number; total: number }) => {
    const { session_id, current, total } = data;
    let onProgress = callbackRegistry[sessionToId[session_id]]?.onProgress;
    onProgress && onProgress(current, total);
  }
);

// Process the media UUID creation
emitter.addListener(
  'media_uuid_created',
  (data: { session_id: string; uuid: string }) => {
    const { session_id, uuid } = data;
    let onUUIDCreated =
      callbackRegistry[sessionToId[session_id]]?.onUUIDCreated;
    onUUIDCreated && onUUIDCreated(uuid);
  }
);

function upload(
  key: string,
  file: {
    uri: string;
    mimeType: string;
  },
  params: {
    onProgress?: ProgressCallback;
    onUUIDCreated?: UUIDCreateCallback;
    metadata?: { [key: string]: string };
  } = {}
) {
  const { uri, mimeType } = file;
  const { onProgress, onUUIDCreated, metadata } = params;
  const deregister = addCallbacks({
    onProgress,
    onUUIDCreated,
  });
  const promise = UploadcareUploader.upload(key, uri, mimeType, metadata || {});
  promise.then(() => onProgress && onProgress(1, 1));
  promise.finally(deregister);
  return promise;
}

export default { upload };
