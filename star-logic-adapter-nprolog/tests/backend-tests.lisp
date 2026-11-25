(defpackage :starlogicadapternprolog-tests
  (:use :cl :fiveam)
  (:import-from :starlogicadapternprolog
                #:nprolog-executable-unavailable-error
                #:nprolog-bridge-unavailable-error
                #:nprolog-package-mismatch-error
                #:nprolog-request-too-large-error
                #:nprolog-malformed-startup-data-error
                #:make-nprolog-backend)
  (:import-from :starlogicprotocol
                #:star-logic-error)
  (:import-from :starprocessport
                #:%make-managed-process))
(in-package :starlogicadapternprolog-tests)

(def-suite starlogicadapternprolog-tests
  :description "Pure and fake-boundary N-Prolog adapter tests.")
(in-suite starlogicadapternprolog-tests)

;; Banner forms observed from the pinned upstream (sasagawa888/nprolog
;; 13d43e0c1b084d736ba15d26f1da085f00224b93, npl 5.20): -v output and the
;; REPL startup line.
(test version-banner-parses-observed-form
  (multiple-value-bind (major minor)
      (starlogicadapternprolog::%parse-version-banner "N-Prolog Ver 5.20")
    (is (= 5 major))
    (is (= 20 minor)))
  (is (string= "5.20"
               (starlogicadapternprolog::%version-string 5 20))))

(test startup-banner-parses-observed-cell-suffix-form
  (multiple-value-bind (major minor)
      (starlogicadapternprolog::%parse-startup-banner
       "N-Prolog Ver 5.20 [30M cells]")
    (is (= 5 major))
    (is (= 20 minor)))
  (multiple-value-bind (major minor)
      (starlogicadapternprolog::%parse-startup-banner "N-Prolog Ver 5.20")
    (is (= 5 major))
    (is (= 20 minor))))

(test version-banners-reject-foreign-forms
  (signals star-logic-error
    (starlogicadapternprolog::%parse-version-banner "SWI-Prolog version 9.2.9"))
  (signals star-logic-error
    (starlogicadapternprolog::%parse-version-banner "N-Prolog Ver x.y"))
  (signals star-logic-error
    (starlogicadapternprolog::%parse-version-banner "N-Prolog Ver "))
  (signals star-logic-error
    (starlogicadapternprolog::%parse-version-banner "")))

(test startup-banner-rejects-junk-suffix
  (signals star-logic-error
    (starlogicadapternprolog::%parse-startup-banner "N-Prolog Ver 5.20 junk")))

;; Observed N-Prolog 5.20: the plain -r REPL emits an ANSI reset before
;; verdicts; machine reads strip ANSI before matching.
(test ansi-stripping-removes-observed-reset
  (is (string= "yes" (starlogicadapternprolog::%strip-ansi-escapes
                      (format nil "~C[0myes" #\Escape))))
  (is (string= (format nil "?- yes~%")
               (starlogicadapternprolog::%strip-ansi-escapes
                (format nil "?- ~C[0myes~%" #\Escape))))
  (is (string= "plain" (starlogicadapternprolog::%strip-ansi-escapes "plain"))))

(test canary-accepts-observed-verdict-forms
  (is (starlogicadapternprolog::%canary-confirmed-p
       (format nil "?- ~C[0myes~C[0m~%" #\Escape #\Escape)))
  (is (starlogicadapternprolog::%canary-confirmed-p (format nil "yes~%")))
  (is (null (starlogicadapternprolog::%canary-confirmed-p (format nil "no~%"))))
  (is (null (starlogicadapternprolog::%canary-confirmed-p ""))))

(test launch-argv-uses-pinned-bridge-consult
  ;; ./-prefixed consult names resolve relative to the child's working
  ;; directory (prolog_file_name branch 0), ahead of NPROLOG_HOME/HOME.
  (let ((argv (starlogicadapternprolog::%nprolog-launch-argv)))
    (is (equal '("-r" "-c" "./star-logic-bridge.pl") argv))))

;; Upstream send_socket/2 writes exactly 256 bytes: payload, strcpy NUL, then
;; uninitialized stack padding. Frames are padded, payloads are bounded at
;; 255 bytes (strcpy overflow would corrupt upstream memory).
(test frame-encoding-pads-to-upstream-write-size
  (let ((frame (starlogicadapternprolog::%encode-bridge-frame "ping")))
    (is (= 256 (length frame)))
    (is (equalp #(112 105 110 103 0) (subseq frame 0 5)))
    (is (every #'zerop (subseq frame 4)))))

(test frame-encoding-preserves-utf-8-and-rejects-oversize
  ;; U+00E9 is two UTF-8 bytes; the frame must carry the exact encoding.
  (let ((frame (starlogicadapternprolog::%encode-bridge-frame
                (format nil "h~Cllo" (code-char #xE9)))))
    (is (equalp #(104 195 169 108 108 111 0)
                (subseq frame 0 7))))
  (signals nprolog-request-too-large-error
    (starlogicadapternprolog::%encode-bridge-frame
     (make-string 256 :initial-element #\a)))
  ;; 255 UTF-8 bytes of payload is exactly at the bound and must encode.
  (is (= 256 (length (starlogicadapternprolog::%encode-bridge-frame
                      (make-string 255 :initial-element #\a))))))

(test frame-encoding-rejects-empty-and-non-strings
  (signals star-logic-error
    (starlogicadapternprolog::%encode-bridge-frame ""))
  (signals star-logic-error
    (starlogicadapternprolog::%encode-bridge-frame nil)))

;; Replies are NUL-terminated by strcpy; everything after the first NUL is
;; upstream stack padding and must be discarded before UTF-8 decoding.
(test payload-decoding-truncates-at-first-nul
  (is (string= "pong"
               (starlogicadapternprolog::%decode-bridge-payload
                (concatenate '(vector (unsigned-byte 8))
                             (babel:string-to-octets "pong" :encoding :utf-8)
                             #(0) (make-array 32 :initial-element 222)))))
  (is (string= "star-logic-nprolog-bridge-1"
               (starlogicadapternprolog::%decode-bridge-payload
                (babel:string-to-octets
                 "star-logic-nprolog-bridge-1" :encoding :utf-8)))))

(test bridge-identity-constants-are-pinned
  (is (string= "star-logic-bridge"
               starlogicadapternprolog::+star-logic-bridge-package-id+))
  (is (string= "star-logic-nprolog-bridge-1"
               starlogicadapternprolog::+star-logic-bridge-protocol+))
  (is (string= "star-logic-bridge.pl"
               starlogicadapternprolog::+star-logic-bridge-file-name+)))

(test shipped-bridge-file-exists-with-digest
  (let ((path (starlogicadapternprolog::%bridge-path)))
    (is (uiop:absolute-pathname-p path))
    (is (uiop:string-prefix-p "sha256:"
                              (starlogicadapternprolog::%sha256-file path)))))

(test port-probe-returns-distinct-free-ports
  (let ((first (starlogicadapternprolog::%probe-free-loopback-port))
        (second (starlogicadapternprolog::%probe-free-loopback-port)))
    (is (and (integerp first) (plusp first) (<= first 65535)))
    (is (and (integerp second) (plusp second)))
    ;; Both probes closed their listeners; the kernel will not hand the same
    ;; port out simultaneously.
    (is (/= first second))))

(test package-expectation-must-match-pinned-bridge-identity
  (let ((backend (starlogicadapternprolog::%make-nprolog-backend
                  :bridge-path "/tmp/star-logic-bridge.pl"
                  :bridge-digest "sha256:abc")))
    (is (starlogicadapternprolog::%validate-package-expectation backend nil nil))
    (is (starlogicadapternprolog::%validate-package-expectation
         backend "star-logic-bridge" "sha256:abc"))
    (signals nprolog-package-mismatch-error
      (starlogicadapternprolog::%validate-package-expectation
       backend "star-logic-bridge" "sha256:wrong"))
    (signals nprolog-package-mismatch-error
      (starlogicadapternprolog::%validate-package-expectation
       backend "other.package" nil))
    (signals nprolog-package-mismatch-error
      (starlogicadapternprolog::%validate-package-expectation
       backend nil "sha256:abc"))))

(test missing-executable-fails-closed
  (signals nprolog-executable-unavailable-error
    (make-nprolog-backend :nprolog-executable
                          "/nonexistent/starlang-nprolog-missing/npl")))

(test startup-banner-bound-allows-exact-limit
  (let ((process
          (starprocessport::%make-managed-process
           :stdout (make-string-input-stream
                    (format nil "N-Prolog Ver 5.20 [30M cells]~%")))))
    (is (string= "N-Prolog Ver 5.20 [30M cells]"
                 (starlogicadapternprolog::%read-startup-banner
                  process :max-chars 28)))))

(test startup-banner-bound-rejects-oversize-before-newline
  (let ((process
          (starprocessport::%make-managed-process
           :stdout (make-string-input-stream
                    (format nil "N-Prolog Ver 5.20 [30M cells]~%")))))
    (signals nprolog-malformed-startup-data-error
      (starlogicadapternprolog::%read-startup-banner process :max-chars 10))))

(test worker-struct-has-no-credential-slot
  ;; The bridge boundary has no authentication data at all. A clean load of
  ;; the worker structure must not grow a slot that could retain secrets.
  (multiple-value-bind (symbol status)
      (find-symbol "NPROLOG-WORKER-PASSWORD" :starlogicadapternprolog)
    (declare (ignore symbol))
    (is (null status))))

(defun run-tests ()
  (run 'starlogicadapternprolog-tests))
