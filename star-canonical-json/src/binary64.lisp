(in-package :starcanonicaljson)

(defconstant +binary64-significand-bits+ 52)
(defconstant +binary64-exponent-bias+ 1023)

(defun %fail-binary64 (message)
  (error 'invalid-canonical-json-error :message message))

(defun %assert-binary64-runtime ()
  (unless (and (= 2 (float-radix 1d0))
               (= 53 (float-digits 1d0))
               (= (rational least-positive-normalized-double-float)
                  (expt 2 -1022))
               (= (rational least-positive-double-float)
                  (expt 2 -1074))
               (= (rational most-positive-double-float)
                  (- (expt 2 1024) (expt 2 971))))
    (%fail-binary64
     "The host double-float representation is not IEEE 754 binary64.")))

(defun %finite-binary64-p (value)
  (handler-case
      (<= (- most-positive-double-float)
          value
          most-positive-double-float)
    (arithmetic-error () nil)))

(defun %log10-power-of-two (exponent)
  (ash (* exponent 78913) -18))

(defun %log10-power-of-five (exponent)
  (ash (* exponent 732923) -20))

(defun %multiple-of-power-p (value base exponent)
  (or (zerop exponent)
      (zerop (mod value (expt base exponent)))))

(defun %exact-shift (value count)
  (if (>= count 0)
      (ash value count)
      (let ((divisor (ash 1 (- count))))
        (multiple-value-bind (quotient remainder)
            (truncate value divisor)
          (unless (zerop remainder)
            (%fail-binary64
             "The host returned a non-binary64 double-float decomposition."))
          quotient))))

(defun %binary64-fields (value)
  (%assert-binary64-runtime)
  (unless (%finite-binary64-p value)
    (%fail-binary64
     "RFC 8785 canonical JSON does not permit NaN or Infinity."))
  (handler-case
      (multiple-value-bind (significand exponent sign)
          (integer-decode-float value)
        (if (zerop significand)
            (values 0 0 nil)
            (let* ((negative-p (minusp sign))
                   (unbiased-exponent
                     (+ (1- (integer-length significand)) exponent)))
              (if (< unbiased-exponent -1022)
                  (let ((mantissa
                          (%exact-shift significand (+ exponent 1074))))
                    (unless (and (plusp mantissa)
                                 (< mantissa (ash 1 +binary64-significand-bits+)))
                      (%fail-binary64
                       "The host returned an invalid binary64 subnormal value."))
                    (values mantissa 0 negative-p))
                  (let* ((shift
                           (- (1+ +binary64-significand-bits+)
                              (integer-length significand)))
                         (normalized (%exact-shift significand shift))
                         (encoded-exponent
                           (+ unbiased-exponent +binary64-exponent-bias+))
                         (mantissa
                           (- normalized
                              (ash 1 +binary64-significand-bits+))))
                    (unless (and (<= 1 encoded-exponent 2046)
                                 (<= 0 mantissa)
                                 (< mantissa
                                    (ash 1 +binary64-significand-bits+)))
                      (%fail-binary64
                       "The host returned an invalid finite binary64 value."))
                    (values mantissa encoded-exponent negative-p))))))
    (arithmetic-error ()
      (%fail-binary64
       "RFC 8785 canonical JSON does not permit NaN or Infinity."))))

(defun %shortest-binary64-decimal (ieee-mantissa ieee-exponent)
  (let* ((e2 (if (zerop ieee-exponent)
                 (- 1 +binary64-exponent-bias+
                    +binary64-significand-bits+ 2)
                 (- ieee-exponent +binary64-exponent-bias+
                    +binary64-significand-bits+ 2)))
         (m2 (if (zerop ieee-exponent)
                 ieee-mantissa
                 (logior (ash 1 +binary64-significand-bits+)
                         ieee-mantissa)))
         (even-p (evenp m2))
         (accept-bounds-p even-p)
         (mv (* 4 m2))
         (mp (+ mv 2))
         (mm-shift (if (or (not (zerop ieee-mantissa))
                           (<= ieee-exponent 1))
                       1
                       0))
         (mm (- mv 1 mm-shift))
         (vr 0)
         (vp 0)
         (vm 0)
         (e10 0)
         (vm-trailing-zero-p nil)
         (vr-trailing-zero-p nil))
    (if (>= e2 0)
        (let* ((q (- (%log10-power-of-two e2)
                     (if (> e2 3) 1 0)))
               (denominator (expt 10 q)))
          (setf e10 q
                vr (floor (ash mv e2) denominator)
                vp (floor (ash mp e2) denominator)
                vm (floor (ash mm e2) denominator))
          (when (<= q 21)
            (cond
              ((zerop (mod mv 5))
               (setf vr-trailing-zero-p
                     (%multiple-of-power-p mv 5 q)))
              (accept-bounds-p
               (setf vm-trailing-zero-p
                     (%multiple-of-power-p mm 5 q)))
              ((%multiple-of-power-p mp 5 q)
               (decf vp)))))
        (let* ((negative-e2 (- e2))
               (q (- (%log10-power-of-five negative-e2)
                     (if (> negative-e2 1) 1 0)))
               (denominator (expt 10 q))
               (scale (expt 5 negative-e2)))
          (setf e10 (+ q e2)
                vr (floor (* mv scale) denominator)
                vp (floor (* mp scale) denominator)
                vm (floor (* mm scale) denominator))
          (cond
            ((<= q 1)
             (setf vr-trailing-zero-p t)
             (if accept-bounds-p
                 (setf vm-trailing-zero-p (= mm-shift 1))
                 (decf vp)))
            ((< q 63)
             (setf vr-trailing-zero-p
                   (%multiple-of-power-p mv 2 q))))))
    (let ((removed 0)
          (last-removed-digit 0)
          (output 0))
      (if (or vm-trailing-zero-p vr-trailing-zero-p)
          (progn
            (loop while (> (floor vp 10) (floor vm 10))
                  do (setf vm-trailing-zero-p
                           (and vm-trailing-zero-p
                                (zerop (mod vm 10)))
                           vr-trailing-zero-p
                           (and vr-trailing-zero-p
                                (zerop last-removed-digit))
                           last-removed-digit (mod vr 10)
                           vp (floor vp 10)
                           vr (floor vr 10)
                           vm (floor vm 10))
                     (incf removed))
            (loop while (and vm-trailing-zero-p
                             (zerop (mod vm 10)))
                  do (setf vr-trailing-zero-p
                           (and vr-trailing-zero-p
                                (zerop last-removed-digit))
                           last-removed-digit (mod vr 10)
                           vp (floor vp 10)
                           vr (floor vr 10)
                           vm (floor vm 10))
                     (incf removed))
            (when (and vr-trailing-zero-p
                       (= last-removed-digit 5)
                       (evenp vr))
              (setf last-removed-digit 4))
            (setf output
                  (+ vr
                     (if (or (and (= vr vm)
                                  (or (not accept-bounds-p)
                                      (not vm-trailing-zero-p)))
                             (>= last-removed-digit 5))
                         1
                         0))))
          (let ((round-up-p nil))
            (loop while (> (floor vp 10) (floor vm 10))
                  do (setf round-up-p (>= (mod vr 10) 5)
                           vp (floor vp 10)
                           vr (floor vr 10)
                           vm (floor vm 10))
                     (incf removed))
            (setf output (+ vr (if (or (= vr vm) round-up-p) 1 0)))))
      (values output (+ e10 removed)))))

(defun %write-decimal-integer (value stream)
  (format stream "~D" value))

(defun %write-shortest-decimal (mantissa exponent negative-p stream)
  (let* ((digits (format nil "~D" mantissa))
         (digit-count (length digits))
         (decimal-point (+ digit-count exponent)))
    (when negative-p
      (write-char #\- stream))
    (cond
      ((and (plusp decimal-point) (<= decimal-point 21))
       (if (>= decimal-point digit-count)
           (progn
             (write-string digits stream)
             (dotimes (ignored (- decimal-point digit-count))
               (declare (ignore ignored))
               (write-char #\0 stream)))
           (progn
             (write-string digits stream :end decimal-point)
             (write-char #\. stream)
             (write-string digits stream :start decimal-point))))
      ((and (<= decimal-point 0) (> decimal-point -6))
       (write-string "0." stream)
       (dotimes (ignored (- decimal-point))
         (declare (ignore ignored))
         (write-char #\0 stream))
       (write-string digits stream))
      (t
       (write-char (char digits 0) stream)
       (when (> digit-count 1)
         (write-char #\. stream)
         (write-string digits stream :start 1))
       (write-char #\e stream)
       (let ((scientific-exponent (1- decimal-point)))
         (when (>= scientific-exponent 0)
           (write-char #\+ stream))
         (%write-decimal-integer scientific-exponent stream))))))

(defun write-canonical-binary64 (value stream)
  (multiple-value-bind (ieee-mantissa ieee-exponent negative-p)
      (%binary64-fields value)
    (if (and (zerop ieee-mantissa) (zerop ieee-exponent))
        (write-char #\0 stream)
        (multiple-value-bind (mantissa exponent)
            (%shortest-binary64-decimal ieee-mantissa ieee-exponent)
          (%write-shortest-decimal mantissa exponent negative-p stream)))))
