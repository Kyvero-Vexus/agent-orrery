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
)
