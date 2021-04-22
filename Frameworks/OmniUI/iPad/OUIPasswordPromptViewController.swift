// Copyright 2017-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import UIKit

open class OUIPasswordPromptViewController: UIViewController, UIViewControllerTransitioningDelegate {
    @IBOutlet var stackView: UIStackView?
    @IBOutlet var backgroundView: UIView?
    @IBOutlet var titleLabel: UILabel?
    @IBOutlet var passwordField: UITextField?
    @IBOutlet var showHintButton: UIButton?
    @IBOutlet var hintLabelButton: UIButton?
    @IBOutlet var hButtonSeparator: UIView?
    @IBOutlet var vButtonSeparator: UIView?
    @IBOutlet var cancelButton: UIButton?
    @IBOutlet var okButton: UIButton?

    @objc var placeholder: String?
    @objc override open var title: String? {
        didSet {
            self.titleLabel?.text = title
        }
    }

    @objc open var hintText: String? {
        didSet {
            self.updateHintText()
        }
    }

    @nonobjc let transitioner = OUIPasswordPromptTransitioner()

    @objc open var handler: ((Bool, String?) -> Swift.Void)?

    override init(nibName: String?, bundle: Bundle?) {
        super.init(nibName: nibName, bundle: bundle)

        self.modalPresentationStyle = .custom
        self.transitioningDelegate = transitioner
    }

    convenience init() {
        self.init(nibName: "OUIPasswordPromptViewController", bundle: OmniUIBundle)
    }

    required public init?(coder: NSCoder) {
        fatalError("NSCoding not supported")
    }

    override open func viewDidLoad() {
        super.viewDidLoad()
        self.titleLabel?.text = title
        self.showHintButton?.setTitle(NSLocalizedString("Show hint…", tableName: "OmniUI", bundle: OmniUIBundle, comment: "Show hint label - password/passphrase prompt"), for: .normal)
        self.cancelButton?.setTitle(NSLocalizedString("Cancel", tableName: "OmniUI", bundle: OmniUIBundle, comment: "button title - password/passphrase prompt"), for: .normal)
        self.okButton?.setTitle(NSLocalizedString("OK", tableName: "OmniUI", bundle: OmniUIBundle, comment: "button title - password/passphrase prompt"), for: .normal)
        self.passwordField?.placeholder = NSLocalizedString("enter password", tableName:"OmniUI", bundle: OmniUIBundle, comment: "password field placeholder text")
        updateHintText()

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.showHintButton?.alpha = 1.0
        self.hintLabelButton?.alpha = 0.0
    }

    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        passwordField?.becomeFirstResponder()
    }

    @IBAction func ok(_ sender:Any) {
        let password = passwordField?.text
        self.presentingViewController?.dismiss(animated: true) {
            self.handler?(true, password)
        }
    }

    @IBAction func cancel(_ sender:Any) {
        self.presentingViewController?.dismiss(animated: true) {
            self.handler?(false, nil)
        }
    }

    @IBAction func showHint(_ sender:Any) {
        let shouldShowHint = self.showHintButton?.alpha != CGFloat(0.0)
        if (shouldShowHint) {
            self.showHintButton?.alpha = 0.0
            UIView.animate(withDuration: 0.25, animations: {
                self.hintLabelButton?.alpha = 1.0
            })
        } else {
            self.hintLabelButton?.alpha = 0.0
            UIView.animate(withDuration: 0.25, animations: {
                self.showHintButton?.alpha = 1.0
            })
        }
    }

    private func updateHintText() {
        guard let hintView = self.showHintButton?.superview else { return }
        self.hintLabelButton?.setTitle(hintText, for: .normal)
        hintView.isHidden = hintText == nil
        stackView?.layoutIfNeeded()
    }

    // MARK: - Notifications (Keyboard)

    @objc func keyboardWillShow(_ notification: Notification) {
        guard let userInfo = notification.userInfo, let keyboardEndFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }

        self.additionalSafeAreaInsets = UIEdgeInsets(top: 0.0, left: 0.0, bottom: keyboardEndFrame.height, right: 0.0)
        self.view.setNeedsLayout()

        animateLayoutDuringKeyboardChange(userInfo: userInfo)
    }

    @objc func keyboardWillHide(_ notification: Notification) {
        self.additionalSafeAreaInsets = UIEdgeInsets.zero
        self.view.setNeedsLayout()

        if let userInfo = notification.userInfo {
            animateLayoutDuringKeyboardChange(userInfo: userInfo)
        }
    }

    private func animateLayoutDuringKeyboardChange(userInfo: [AnyHashable: Any]) {

        guard let curve = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int, let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else {
            return
        }

        let options: UIView.AnimationOptions = [(UIView.AnimationOptions(rawValue: UIView.AnimationOptions.RawValue(curve << 16))), .beginFromCurrentState]

        UIView.animate(withDuration: duration, delay: 0.0, options: options, animations: {
            self.view.layoutIfNeeded()
        }, completion: nil)
    }

}

class OUIPasswordPromptPresentationController : UIPresentationController {
    @objc func decorateView(_ v:UIView) {
        v.layer.cornerRadius = 8
        v.layer.masksToBounds = true

        let m1 = UIInterpolatingMotionEffect(keyPath: "center.x", type: .tiltAlongHorizontalAxis)
        m1.maximumRelativeValue = 10.0
        m1.minimumRelativeValue = -10.0
        let m2 = UIInterpolatingMotionEffect(keyPath: "center.y", type: .tiltAlongVerticalAxis)
        m2.maximumRelativeValue = 10.0
        m2.minimumRelativeValue = -10.0
        let g = UIMotionEffectGroup()
        g.motionEffects = [m1,m2]
        v.addMotionEffect(g)
    }

    override func presentationTransitionWillBegin() {
        guard let passwordPromptViewController = self.presentedViewController as? OUIPasswordPromptViewController else { return }
        self.decorateView(passwordPromptViewController.backgroundView!)
        let presentingViewController = self.presentingViewController
        let presentingView = presentingViewController.view!
        let containerView = self.containerView!
        let shadow = UIView(frame: containerView.bounds)
        shadow.backgroundColor = UIColor(white:0, alpha:0.4)
        shadow.alpha = 0.0
        containerView.insertSubview(shadow, at: 0)
        shadow.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let transitionCoordinator = presentingViewController.transitionCoordinator!
        transitionCoordinator.animate(alongsideTransition: { _ in
            shadow.alpha = 1.0
        }) { _ in
            presentingView.tintAdjustmentMode = .dimmed
        }
    }

    override func dismissalTransitionWillBegin() {
        let presentingViewController = self.presentingViewController
        let presentingView = presentingViewController.view!
        let containerView = self.containerView!
        let shadow = containerView.subviews[0]
        let transitionCoordinator = presentingViewController.transitionCoordinator!
        transitionCoordinator.animate(alongsideTransition: { _ in
            shadow.alpha = 0.0
        }) { _ in
            presentingView.tintAdjustmentMode = .automatic
        }
    }

    override var frameOfPresentedViewInContainerView : CGRect {
        let frame = containerView!.bounds
        presentedView!.frame = frame
        return frame
    }

}

class OUIPasswordPromptTransitioner : NSObject, UIViewControllerTransitioningDelegate {
    func presentationController( forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        return OUIPasswordPromptPresentationController(presentedViewController: presented, presenting: presenting)
    }

    func animationController(forPresented presented:UIViewController, presenting: UIViewController,
        source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
            return self
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
            return self
    }
}

extension OUIPasswordPromptTransitioner : UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
            return 0.25
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let con = transitionContext.containerView

        let fromView = transitionContext.view(forKey: .from)
        let toView = transitionContext.view(forKey: .to)

        if let toView = toView { // presenting
            con.addSubview(toView)
            let scale = CGAffineTransform(scaleX: 1.6, y: 1.6)
            toView.transform = scale
            toView.alpha = 0.0
            UIView.animate(withDuration: 0.25, animations: {
                toView.alpha = 1.0
                toView.transform = .identity
            }) { _ in
                transitionContext.completeTransition(true)
            }
        } else if let fromView = fromView { // dismissing
            UIView.animate(withDuration: 0.25, animations: {
                fromView.alpha = 0.0
            }) { _ in
                transitionContext.completeTransition(true)
            }
        }
    }
}
