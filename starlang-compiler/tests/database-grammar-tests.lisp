(defpackage :starlang-database-grammar-tests
  (:use :cl :fiveam)
  (:export #:run-tests))

(in-package :starlang-database-grammar-tests)

(def-suite database-grammar-tests
  :description "Closed StarLang database declaration grammar.")

(in-suite database-grammar-tests)

(defun compile-source (source)
  (starlangcompiler:compile-spec-library
   (starlangcompiler:read-star-syntax
    source :source-id "database-grammar-test.star")))

(defun database-source (&optional operation-extra)
  (format nil
          "(spec-library \"test/database@1\" (:version \"1.0.0\")
             (document person (:persistence transient)
               (name string :required))
             (database intel (:access read-write))
             (database-operation person-by-id
               (:database intel
                :access read
                :kind lookup
                :parameters ((id string :required))
                :result person
                :cardinality optional-one
                :idempotency readonly
                :capabilities (databaseRead)
                :timeout-ms 1000
                :result-limit 1~A)))"
          (or operation-extra "")))

(defun declaration-of-kind (library kind)
  (find kind (getf library :declarations)
        :key (lambda (item) (getf item :kind))
        :test #'eq))

(test database-and-operation-compile-to-normalized-ir
  (let* ((library (compile-source (database-source)))
         (database (declaration-of-kind library :database))
         (operation (declaration-of-kind library :database-operation)))
    (is (equal "intel" (getf database :name)))
    (is (eq :read-write (getf database :access)))
    (is (equal "person-by-id" (getf operation :name)))
    (is (equal "intel" (getf operation :database)))
    (is (eq :read (getf operation :access)))
    (is (eq :lookup (getf operation :operation-kind)))
    (is (eq :optional-one (getf operation :cardinality)))
    (is (eq :readonly (getf operation :idempotency)))
    (is (equal '("databaseRead") (getf operation :capabilities)))
    (is (= 1000 (getf operation :timeout-ms)))
    (is (= 1 (getf operation :result-limit)))
    (is (equal "test/database@1/person" (getf operation :result)))
    (is (equal "id" (getf (first (getf operation :parameters)) :name)))))

(test database-options-are-closed
  (signals error
    (compile-source
     "(spec-library \"test/database@1\" (:version \"1\")
        (database intel (:access read :dsn \"postgres://secret\")))"))
  (signals error
    (compile-source
     (database-source " :sql \"select * from people\"")))
  (signals error
    (compile-source
     (database-source " :database intel"))))

(test database-values-are-closed
  (signals error
    (compile-source
     "(spec-library \"test/database@1\" (:version \"1\")
        (database intel (:access superuser)))"))
  (signals error
    (compile-source
     "(spec-library \"test/database@1\" (:version \"1\")
        (database intel (:access read))
        (database-operation q
          (:database intel :access root :kind lookup
           :parameters () :result string :cardinality one
           :idempotency readonly :capabilities (databaseRead))))")))

(test operation-requires-known-logical-database
  (signals error
    (compile-source
     "(spec-library \"test/database@1\" (:version \"1\")
        (database-operation orphan
          (:database missing :access read :kind lookup
           :parameters () :result string :cardinality one
           :idempotency readonly :capabilities (databaseRead))))")))

(test database-operation-bounds-are-positive
  (signals error
    (compile-source (database-source " :timeout-ms 0")))
  (signals error
    (compile-source (database-source " :result-limit -1"))))

(test capabilities-are-unique
  (signals error
    (compile-source
     (database-source " :capabilities (databaseRead databaseRead)"))))

(defun run-tests ()
  (unless (run! 'database-grammar-tests)
    (error "StarLang database grammar tests failed.")))
