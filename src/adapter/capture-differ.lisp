;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;
;;; capture-differ.lisp — Typed diffing for capture-result regression detection

(in-package #:orrery/adapter)

(deftype diff-classification ()
  '(member :identical :compatible :regressed :improved :new :removed))

(defstruct (endpoint-delta
             (:constructor make-endpoint-delta
                 (&key endpoint classification
                       status-before status-after
                       body-changed-p latency-delta-ms detail))
             (:conc-name ed-))
  (endpoint "" :type string)
  (classification :identical :type diff-classification)
  (status-before 0 :type (integer 0 999))
  (status-after 0 :type (integer 0 999))
  (body-changed-p nil :type boolean)
  (latency-delta-ms 0 :type integer)
  (detail "" :type string))

(defstruct (capture-diff
             (:constructor make-capture-diff
                 (&key diff-id deltas endpoint-count
                       identical-count compatible-count
                       regressed-count improved-count
                       new-count removed-count
                       regressions-p))
             (:conc-name cd-))
  (diff-id "" :type string)
  (deltas '() :type list)
  (endpoint-count 0 :type (integer 0))
  (identical-count 0 :type (integer 0))
  (compatible-count 0 :type (integer 0))
  (regressed-count 0 :type (integer 0))
  (improved-count 0 :type (integer 0))
  (new-count 0 :type (integer 0))
  (removed-count 0 :type (integer 0))
  (regressions-p nil :type boolean))

(declaim (ftype (function (endpoint-sample endpoint-sample)
                          (values endpoint-delta &optional))
                diff-endpoint-samples))
(defun diff-endpoint-samples (before after)
  (declare (optimize (safety 3)))
  (let* ((status-before (es-status-code before))
         (status-after (es-status-code after))
         (body-before (es-body before))
         (body-after (es-body after))
         (body-changed (not (string= body-before body-after)))
         (lat-delta (- (es-latency-ms after) (es-latency-ms before)))
         (class (cond
                  ((and (= status-before status-after) (not body-changed)) :identical)
                  ((and (< status-before 400) (< status-after 400))
                   (if (> lat-delta 250) :compatible :improved))
                  ((and (>= status-before 400) (< status-after 400)) :improved)
                  ((and (< status-before 400) (>= status-after 400)) :regressed)
                  (t :compatible))))
    (make-endpoint-delta
     :endpoint (es-endpoint before)
     :classification class
     :status-before status-before
     :status-after status-after
     :body-changed-p body-changed
     :latency-delta-ms lat-delta
     :detail (format nil "~A->~A body~:[-same~;+changed~] latΔ=~D"
                     status-before status-after body-changed lat-delta))))

(declaim (ftype (function (capture-result capture-result &key (:diff-id string))
                          (values capture-diff &optional))
                diff-capture-results))
(defun diff-capture-results (before after &key (diff-id ""))
  (declare (optimize (safety 3)))
  (let ((before-map (make-hash-table :test 'equal))
        (after-map (make-hash-table :test 'equal))
        (deltas '())
        (identical 0) (compatible 0) (regressed 0)
        (improved 0) (new 0) (removed 0))
    (dolist (s (cres-snapshots before))
      (when (endpoint-sample-p s)
        (setf (gethash (es-endpoint s) before-map) s)))
    (dolist (s (cres-snapshots after))
      (when (endpoint-sample-p s)
        (setf (gethash (es-endpoint s) after-map) s)))

    ;; Present in AFTER (new or changed)
    (maphash
     (lambda (endpoint after-s)
       (let ((before-s (gethash endpoint before-map)))
         (if before-s
             (let ((d (diff-endpoint-samples before-s after-s)))
               (push d deltas)
               (ecase (ed-classification d)
                 (:identical (incf identical))
                 (:compatible (incf compatible))
                 (:regressed (incf regressed))
                 (:improved (incf improved))
                 (:new (incf new))
                 (:removed (incf removed))))
             (progn
               (push (make-endpoint-delta
                      :endpoint endpoint
                      :classification :new
                      :status-before 0
                      :status-after (es-status-code after-s)
                      :body-changed-p t
                      :latency-delta-ms (es-latency-ms after-s)
                      :detail "new endpoint")
                     deltas)
               (incf new)))))
     after-map)

    ;; Removed endpoints
    (maphash
     (lambda (endpoint before-s)
       (declare (ignore before-s))
       (unless (gethash endpoint after-map)
         (push (make-endpoint-delta
                :endpoint endpoint
                :classification :removed
                :status-before (es-status-code (gethash endpoint before-map))
                :status-after 0
                :body-changed-p t
                :latency-delta-ms (- (es-latency-ms (gethash endpoint before-map)))
                :detail "removed endpoint")
               deltas)
         (incf removed)))
     before-map)

    (let* ((endpoint-count (length deltas))
           (ordered-deltas (nreverse deltas)))
      (make-capture-diff
       :diff-id diff-id
       :deltas ordered-deltas
       :endpoint-count endpoint-count
       :identical-count identical
       :compatible-count compatible
       :regressed-count regressed
       :improved-count improved
       :new-count new
       :removed-count removed
       :regressions-p (> regressed 0)))))

(declaim (ftype (function (capture-diff) (values string &optional))
                capture-diff-to-json))
(defun capture-diff-to-json (diff)
  (declare (optimize (safety 3)))
  (format nil "{\"diff_id\":\"~A\",\"endpoint_count\":~D,\"identical_count\":~D,~
               \"compatible_count\":~D,\"regressed_count\":~D,\"improved_count\":~D,~
               \"new_count\":~D,\"removed_count\":~D,\"regressions\":~A}"
          (cd-diff-id diff)
          (cd-endpoint-count diff)
          (cd-identical-count diff)
          (cd-compatible-count diff)
          (cd-regressed-count diff)
          (cd-improved-count diff)
          (cd-new-count diff)
          (cd-removed-count diff)
          (if (cd-regressions-p diff) "true" "false")))
