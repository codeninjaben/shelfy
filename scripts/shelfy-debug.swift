// Debug builds only: scripts/shelfy-debug.swift <command>
// Commands: expand hover collapse grid select-first popover settings close-settings arrival clear quicklook
//           rearm-approach trash-sim undo
import Foundation
let command = CommandLine.arguments.dropFirst().first ?? "expand"
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.benbreslow.Shelfy.debug.\(command)"), object: nil, userInfo: nil, deliverImmediately: true)
