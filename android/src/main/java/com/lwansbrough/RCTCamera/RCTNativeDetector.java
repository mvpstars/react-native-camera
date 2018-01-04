package com.lwansbrough.RCTCamera;

import android.hardware.Camera;

import com.facebook.react.bridge.ReactContext;
import com.facebook.react.modules.core.DeviceEventManagerModule;

import javax.annotation.Nullable;

/**
 * Created by paiou on 03/01/18.
 */
public abstract class RCTNativeDetector {
    /**
     * Method called when a new preview frame is available, and no other native detection is running
     *
     * @param camera Camera instance that generated the frame
     * @param data   Image data
     */
    public abstract void process(Camera camera, byte[] data);

    /**
     * Notify a detection to JS
     *
     * @param data Result to be sent to onDetection JS callback
     */
    protected void notifyDetection(@Nullable Object data) {
        ReactContext reactContext = RCTCameraModule.getReactContextSingleton();
        reactContext.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class).emit("CameraDetectionAndroid", data);
    }

    /**
     * Signal to the Camera that the detection is completed, and remove task lock
     * This method MUST be called after each detection task (triggered by a call to process method) is completed.
     * process method will not be called anymore until this is called.
     */
    protected void detectorTaskCompleted() {
        RCTCameraViewFinder.nativeDetectorTaskLock = false;
    }
}
