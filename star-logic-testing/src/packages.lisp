(defpackage :starlogictesting
  (:use :cl)
  (:nicknames :star-logic-testing)
  (:import-from :starlogicprotocol
                #:+logic-operation-running+
                #:+logic-operation-completed+
                #:+logic-operation-no-answer+
                #:+logic-operation-cancelled+
                #:logic-session-error
                #:unsupported-logic-operation-error
                #:make-logic-backend-descriptor
                #:logic-backend-descriptor-id
                #:logic-backend-descriptor-of
                #:open-logic-session
                #:close-logic-session
                #:apply-logic-fact-delta
                #:invoke-logic-operation
                #:next-logic-result
                #:cancel-logic-operation
                #:logic-operation-status
                #:logic-backend-health)
  (:export
   #:fake-logic-backend
   #:fake-logic-backend-p
   #:make-fake-logic-backend
   #:fake-logic-session
   #:fake-logic-session-p
   #:fake-logic-session-id
   #:fake-logic-session-deltas))
