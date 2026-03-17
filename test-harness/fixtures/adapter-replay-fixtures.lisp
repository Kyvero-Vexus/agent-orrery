(
 (:surface :tui
  :kind :status
  :payload ((:id . "tui-status-42") (:timestamp . 42) (:state . :ok))
  :source "replay:tui")
 (:surface :web
  :kind :session
  :payload ((:session-id . "s-1") (:agent . "gensym") (:model . "gpt") (:status . :active))
  :source "replay:web")
 (:surface :mcclim
  :kind :analytics
  :payload ((:total-sessions . 7) (:total-cost-cents . 123))
  :source "replay:mcclim")
 ;; Expanded corpus (ckx): cost/capacity/audit/analytics across surfaces
 (:surface :web
  :kind :cost
  :payload ((:recommended-model . "gpt-4o-mini") (:confidence . "high"))
  :source "replay:web:cost")
 (:surface :tui
  :kind :capacity
  :payload ((:zone . "warning") (:headroom-pct . 23))
  :source "replay:tui:capacity")
 (:surface :mcclim
  :kind :audit
  :payload ((:seq . 12) (:category . "session-lifecycle") (:hash . "abc123"))
  :source "replay:mcclim:audit")
 (:surface :web
  :kind :analytics
  :payload ((:total-sessions . 12) (:total-cost-cents . 456))
  :source "replay:web:analytics")
)
