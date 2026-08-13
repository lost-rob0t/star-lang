(require :asdf)

(load (merge-pathnames "star-loader.lisp" *load-truename*))
(load (merge-pathnames "resolver-effect-ports-prototype.lisp" *load-truename*))
(load (merge-pathnames "resolver-shell-effects-prototype.lisp" *load-truename*))

(in-package #:star-lang.loader)

(defparameter *resolver-test-digest-a*
  "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
(defparameter *resolver-test-digest-b*
  "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")

(defun resolver-test-assert (condition label)
  (unless condition
    (error "Resolver effect assertion failed: ~A" label)))

(defun resolver-test-condition-p (type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (caught)
      (if (typep caught type)
          t
          (error caught)))))

(defun resolver-test-directory ()
  (let ((directory
          (merge-pathnames
           (format nil "star-resolver-effects-~36R-~36R/"
                   (get-universal-time)
                   (random most-positive-fixnum))
           (uiop:temporary-directory))))
    (ensure-directories-exist (merge-pathnames #P".keep" directory))
    directory))

(defun resolver-test-write (pathname content)
  (ensure-directories-exist pathname)
  (with-open-file (stream pathname
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (write-string content stream))
  pathname)

(defun make-fake-resolver-effects
    (&key
       (digest *resolver-test-digest-a*)
       (content
         "(spec-library \"test/root@1\" (:version \"1.0.0\") (document item (:persistence persistent) (id string :required)))")
       fetch-counter
       digest-counter)
  (star-lang.loader.effects:make-resolver-effects
   :digest-file
   (lambda (pathname)
     (declare (ignore pathname))
     (when digest-counter
       (incf (car digest-counter)))
     digest)
   :fetch-to-file
   (lambda (url destination
            &key maximum-bytes maximum-redirects connect-timeout
              read-timeout deadline proxy)
     (declare (ignore maximum-bytes maximum-redirects connect-timeout
                      read-timeout deadline proxy))
     (when fetch-counter
       (incf (car fetch-counter)))
     (resolver-test-write destination content)
     (list :requested-uri url
           :final-uri url
           :bytes (length content)))))

(defun test-injected-root-fetch ()
  (let* ((directory (resolver-test-directory))
         (cache (merge-pathnames #P"cache/" directory))
         (fetch-counter (list 0))
         (digest-counter (list 0))
         (effects
           (make-fake-resolver-effects
            :fetch-counter fetch-counter
            :digest-counter digest-counter)))
    (unwind-protect
         (let ((graph
                 (load-star-url
                  "https://example.invalid/root.star"
                  :name "test/root@1"
                  :version "1.0.0"
                  :digest *resolver-test-digest-a*
                  :allow-network t
                  :cache-directory cache
                  :resolver-effects effects)))
           (resolver-test-assert
            (string= "test/root@1"
                     (library-node-name (loaded-graph-root graph)))
            "fake fetch loads requested root")
           (resolver-test-assert (= 1 (car fetch-counter))
                                 "remote miss invokes fetch exactly once")
           (resolver-test-assert (> (car digest-counter) 0)
                                 "digest verification uses injected digest effect"))
      (uiop:delete-directory-tree directory
                                  :validate t
                                  :if-does-not-exist :ignore))))

(defun test-network-disabled-never-fetches ()
  (let* ((directory (resolver-test-directory))
         (cache (merge-pathnames #P"cache/" directory))
         (fetch-counter (list 0))
         (effects
           (make-fake-resolver-effects :fetch-counter fetch-counter)))
    (unwind-protect
         (progn
           (resolver-test-assert
            (resolver-test-condition-p
             'network-disabled-error
             (lambda ()
               (load-star-url
                "https://example.invalid/root.star"
                :name "test/root@1"
                :version "1.0.0"
                :digest *resolver-test-digest-a*
                :allow-network nil
                :cache-directory cache
                :resolver-effects effects)))
            "offline remote miss signals network-disabled-error")
           (resolver-test-assert (= 0 (car fetch-counter))
                                 "offline remote miss never invokes fetch effect"))
      (uiop:delete-directory-tree directory
                                  :validate t
                                  :if-does-not-exist :ignore))))

(defun test-cache-hit-never-refetches ()
  (let* ((directory (resolver-test-directory))
         (cache (merge-pathnames #P"cache/" directory))
         (fetch-counter (list 0))
         (effects
           (make-fake-resolver-effects :fetch-counter fetch-counter)))
    (unwind-protect
         (progn
           (load-star-url
            "https://example.invalid/root.star"
            :name "test/root@1"
            :version "1.0.0"
            :digest *resolver-test-digest-a*
            :allow-network t
            :cache-directory cache
            :resolver-effects effects)
           (resolver-test-assert (= 1 (car fetch-counter))
                                 "initial cache miss fetches once")
           (load-star-url
            "https://example.invalid/root.star"
            :name "test/root@1"
            :version "1.0.0"
            :digest *resolver-test-digest-a*
            :allow-network nil
            :cache-directory cache
            :resolver-effects effects)
           (resolver-test-assert (= 1 (car fetch-counter))
                                 "offline cache hit does not refetch"))
      (uiop:delete-directory-tree directory
                                  :validate t
                                  :if-does-not-exist :ignore))))

(defun test-digest-mismatch-precedes-parse ()
  (let* ((directory (resolver-test-directory))
         (cache (merge-pathnames #P"cache/" directory))
         (fetch-counter (list 0))
         (effects
           (make-fake-resolver-effects
            :digest *resolver-test-digest-b*
            :content "#.(error \"must-not-parse\")"
            :fetch-counter fetch-counter)))
    (unwind-protect
         (progn
           (resolver-test-assert
            (resolver-test-condition-p
             'digest-error
             (lambda ()
               (load-star-url
                "https://example.invalid/root.star"
                :name "test/root@1"
                :version "1.0.0"
                :digest *resolver-test-digest-a*
                :allow-network t
                :cache-directory cache
                :resolver-effects effects)))
            "digest mismatch is rejected before parsing fetched bytes")
           (resolver-test-assert (= 1 (car fetch-counter))
                                 "mismatch test fetched exactly once"))
      (uiop:delete-directory-tree directory
                                  :validate t
                                  :if-does-not-exist :ignore))))

(defun test-invalid-digest-effect-result-is-typed ()
  (let ((effects
          (star-lang.loader.effects:make-resolver-effects
           :digest-file (lambda (pathname)
                          (declare (ignore pathname))
                          "not-a-digest")
           :fetch-to-file (lambda (&rest arguments)
                            (declare (ignore arguments))
                            (error "unused")))))
    (resolver-test-assert
     (resolver-test-condition-p
      'digest-error
      (lambda ()
        (let ((*resolver-effects* effects))
          (sha256-file #P"unused.star"))))
     "malformed adapter digest is normalized through loader policy")))

(defun run-resolver-effect-port-tests ()
  (test-injected-root-fetch)
  (test-network-disabled-never-fetches)
  (test-cache-hit-never-refetches)
  (test-digest-mismatch-precedes-parse)
  (test-invalid-digest-effect-result-is-typed)
  (format t "Resolver effect port tests passed.~%")
  t)

(unless (run-resolver-effect-port-tests)
  (error "Resolver effect port tests failed."))
