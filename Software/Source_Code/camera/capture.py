import cv2
import contextlib
import os
import threading


@contextlib.contextmanager
def _silent_stderr():
    with open(os.devnull, "w") as devnull:
        with contextlib.redirect_stderr(devnull):
            yield


class CameraCapture:
    BACKEND_NAMES = {
        cv2.CAP_ANY: "Auto",
        cv2.CAP_DSHOW: "DirectShow",
        cv2.CAP_MSMF: "MSMF",
    }
    REQUEST_WIDTH = 1920
    REQUEST_HEIGHT = 1080

    def __init__(self, camera_id=0):
        self.camera_id = camera_id
        self.cap = None
        self.backend = None
        self.frame_width = 0
        self.frame_height = 0
        self._latest_frame = None
        self._frame_lock = threading.Lock()
        self._grab_running = False
        self._grab_thread = None

    def _grab_loop(self):
        while self._grab_running and self.cap is not None:
            try:
                with _silent_stderr():
                    ret, frame = self.cap.read()
                if ret and frame is not None:
                    with self._frame_lock:
                        self._latest_frame = frame
            except Exception:
                pass

    def _start_grab_thread(self):
        if self._grab_running:
            return
        self._grab_running = True
        self._grab_thread = threading.Thread(target=self._grab_loop, daemon=True, name="CamGrab")
        self._grab_thread.start()

    def _stop_grab_thread(self):
        self._grab_running = False
        if self._grab_thread is not None and self._grab_thread.is_alive():
            self._grab_thread.join(timeout=1.0)
        self._grab_thread = None

    def open(self, camera_id=None):
        if camera_id is not None:
            self.camera_id = camera_id
        self.release()

        strategies = [
            ("CAP_DSHOW", cv2.CAP_DSHOW),
            ("CAP_MSMF", cv2.CAP_MSMF),
        ]

        for name, backend in strategies:
            try:
                with _silent_stderr():
                    cap = cv2.VideoCapture(self.camera_id, backend)

                if not cap.isOpened():
                    cap.release()
                    continue

                cap.set(cv2.CAP_PROP_FRAME_WIDTH, self.REQUEST_WIDTH)
                cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self.REQUEST_HEIGHT)

                try:
                    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
                except Exception:
                    pass
                try:
                    cap.set(cv2.CAP_PROP_FPS, 30)
                except Exception:
                    pass

                self.cap = cap
                self.backend = backend
                self.frame_width = self.REQUEST_WIDTH
                self.frame_height = self.REQUEST_HEIGHT

                self._warm_up()
                self._start_grab_thread()

                return True

            except Exception:
                cap.release() if 'cap' in locals() else None

        raise RuntimeError(
            f"Failed to open camera {self.camera_id} with any backend."
        )

    def _warm_up(self, timeout_ms=3000):
        if self.cap is None:
            return
        done = threading.Event()
        count = [0]
        def _grab():
            for _ in range(3):
                try:
                    with _silent_stderr():
                        if self.cap.grab():
                            count[0] += 1
                except Exception:
                    pass
            done.set()
        t = threading.Thread(target=_grab, daemon=True)
        t.start()
        done.wait(timeout_ms / 1000.0)

    def read_frame(self, timeout_ms=3000):
        if self.cap is None or not self.cap.isOpened():
            return None
        with self._frame_lock:
            frame = self._latest_frame
            self._latest_frame = None
        return frame

    def is_opened(self):
        return self.cap is not None and self.cap.isOpened()

    def release(self):
        self._stop_grab_thread()
        if self.cap is not None:
            try:
                with _silent_stderr():
                    self.cap.release()
            except Exception:
                pass
            self.cap = None
        self.frame_width = 0
        self.frame_height = 0

    @staticmethod
    def list_cameras(max_cameras=5):
        available = []
        for i in range(max_cameras):
            for backend in [cv2.CAP_DSHOW, cv2.CAP_ANY]:
                try:
                    with _silent_stderr():
                        cap = cv2.VideoCapture(i, backend)
                    if cap.isOpened():
                        available.append(i)
                        cap.release()
                        break
                    cap.release()
                except Exception:
                    pass
        return available
