import Foundation
import UIKit
import CarPlay

/// CarPlay integration — quick-start a round when you arrive at the course
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        let rootTemplate = buildRootTemplate()
        interfaceController.setRootTemplate(rootTemplate, animated: true, completion: nil)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }

    private func buildRootTemplate() -> CPTemplate {
        // Main grid with quick actions
        let startRoundButton = CPGridButton(
            titleVariants: ["Start Round"],
            image: UIImage(systemName: "flag.fill")!
        ) { [weak self] _ in
            self?.handleStartRound()
        }

        let resumeRoundButton = CPGridButton(
            titleVariants: ["Resume Round"],
            image: UIImage(systemName: "play.fill")!
        ) { [weak self] _ in
            self?.handleResumeRound()
        }

        let statsButton = CPGridButton(
            titleVariants: ["My Handicap"],
            image: UIImage(systemName: "number")!
        ) { [weak self] _ in
            self?.showHandicap()
        }

        let template = CPGridTemplate(
            title: "AI Caddy",
            gridButtons: [startRoundButton, resumeRoundButton, statsButton]
        )

        return template
    }

    private func handleStartRound() {
        // Signal the app to open with start-round intent
        UserDefaults.standard.set(true, forKey: "carplay_start_round")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "carplay_start_time")

        let alert = CPAlertTemplate(
            titleVariants: ["Opening AI Caddy"],
            actions: [CPAlertAction(title: "OK", style: .default, handler: { _ in })]
        )
        interfaceController?.presentTemplate(alert, animated: true, completion: nil)
    }

    private func handleResumeRound() {
        UserDefaults.standard.set(true, forKey: "carplay_resume_round")

        let alert = CPAlertTemplate(
            titleVariants: ["Resuming your round"],
            actions: [CPAlertAction(title: "OK", style: .default, handler: { _ in })]
        )
        interfaceController?.presentTemplate(alert, animated: true, completion: nil)
    }

    private func showHandicap() {
        let handicap = UserDefaults.standard.double(forKey: "current_handicap")
        let message = handicap > 0 ? String(format: "Your handicap: %.1f", handicap) : "Play 3+ rounds to calculate"

        let alert = CPAlertTemplate(
            titleVariants: [message],
            actions: [CPAlertAction(title: "OK", style: .default, handler: { _ in })]
        )
        interfaceController?.presentTemplate(alert, animated: true, completion: nil)
    }
}
