#!/usr/bin/env -S sbcl --script
(require :asdf)
(defparameter *root*
  (uiop:pathname-parent-directory-pathname
   (uiop:pathname-directory-pathname *load-truename*)))
(push *root* asdf:*central-registry*)
(asdf:load-asd (merge-pathnames "star-scrape/star-scrape.asd" *root*))
(asdf:load-system :star-scrape)
(asdf:load-system :ironclad)
(asdf:load-system :babel)

(defun digest-text (text)
  (ironclad:byte-array-to-hex-string
   (ironclad:digest-sequence :sha256 (babel:string-to-octets text :encoding :utf-8))))
(defun newline (text) (format nil "~A~%" (string-right-trim '(#\Newline #\Return) text)))
(defun outputs ()
  (let* ((source (merge-pathnames "fixtures/star-scrape-core-v2.star" *root*))
         (vocabulary (starscrape.schema:load-scraper-vocabulary source
                      :expected-name "org.starscrape/scraper@2"))
         (manifest (newline (starcanonicaljson:canonical-manifest-json vocabulary)))
         (schema (newline (starlangcompiler:generate-json-schema vocabulary)))
         (lock (newline (starcanonicaljson:canonical-manifest-json
                        (list :vocabulary "org.starscrape/scraper@2"
                              :version "2.0.0" :starintel-version "0.10.1"
                              :source-sha256 (digest-text (uiop:read-file-string source))
                              :manifest-sha256 (digest-text manifest)
                              :schema-sha256 (digest-text schema))))))
    (list (cons "portable-manifest.json" manifest)
          (cons "schema.json" schema) (cons "bundle-lock.json" lock))))
(let* ((args (uiop:command-line-arguments))
       (check-p (equal args '("--check")))
       (directory (if (and (= (length args) 2) (equal (first args) "--output-directory"))
                      (uiop:ensure-directory-pathname (second args))
                      (merge-pathnames "specs/scraper/2.0.0/generated/" *root*))))
  (unless (or (null args) check-p
              (and (= (length args) 2) (equal (first args) "--output-directory")))
    (error "Usage: generate-scraper-release.lisp [--check | --output-directory DIR]"))
  (dolist (entry (outputs))
    (let ((path (merge-pathnames (car entry) directory)))
      (if check-p
          (unless (and (probe-file path) (string= (cdr entry) (uiop:read-file-string path)))
            (error "Missing or stale generated scraper artifact: ~A" path))
          (progn
            (ensure-directories-exist path)
            (with-open-file (stream path :direction :output :if-exists :supersede
                                        :if-does-not-exist :create :external-format :utf-8)
              (write-string (cdr entry) stream))))))
  (format t "Scraper 2.0.0 artifacts ~:[generated~;verified~].~%" check-p))
