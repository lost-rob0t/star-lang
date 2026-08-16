(defpackage :starlangcompiler
  (:use :cl)
  (:nicknames :starlang-compiler)
  (:import-from :starlogicir
                #:+logic-backend-auto+
                #:make-logic-call
                #:logic-call-source-span
                #:materialize-logic-call
                #:invalid-logic-backend-policy-error
                #:invalid-logic-operation-error
                #:invalid-logic-package-identity-error
                #:invalid-logic-value-error)
  (:import-from :starlogicprotocol
                #:logic-backend-not-found-error
                #:logic-backend-incompatible-error
                #:logic-backend-selection-error)
  (:export
   #:logic-policy-compiler-error
   #:logic-policy-compiler-error-message
   #:logic-policy-compiler-error-code
   #:logic-policy-compiler-error-source-span
   #:logic-policy-compiler-error-cause
   #:compile-logic-call
   #:materialize-compiled-logic-call))
