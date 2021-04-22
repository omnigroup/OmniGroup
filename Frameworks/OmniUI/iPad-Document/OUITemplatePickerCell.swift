// Copyright 2017-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import QuickLookThumbnailing

class OUITemplatePickerCell: UICollectionViewCell {

    @IBOutlet private(set) weak var preview: UIImageView!
    @IBOutlet private(set) weak var displayName: UILabel!
    @IBOutlet private var previewFullWidthConstraint: NSLayoutConstraint!
    @IBOutlet private var previewFullHeightConstraint: NSLayoutConstraint!

    var templateItem: OUITemplateItem? {
        didSet {
            updateThumbnail()
        }
    }

    private var _previewAspectRatio: CGFloat = 1.0
    private var previewAspectRatioConstraint: NSLayoutConstraint?

    private var previewAspectRatio: CGFloat {
        get {
            return _previewAspectRatio
        }

        set {
            guard newValue != _previewAspectRatio else { return } // Avoid unnecessary changes to our constraints
            _previewAspectRatio = newValue
            guard let preview = preview else { return }
            let constraint = NSLayoutConstraint(item: preview, attribute: .width, relatedBy: .equal, toItem: preview, attribute: .height, multiplier: newValue, constant: 0.0)
            self.previewAspectRatioConstraint?.isActive = false
            constraint.isActive = true
            self.previewAspectRatioConstraint = constraint
        }
    }

    func willDisplay() {
        updateThumbnail()
    }

    // MARK:- UICollectionViewCell subclass

    override func prepareForReuse() {
        super.prepareForReuse()

        updatePreview(nil)
    }

    // MARK:- UIView subclass

    override func awakeFromNib() {
        super.awakeFromNib()

        preview.layer.masksToBounds = true

        preview.layer.cornerRadius = 5
        preview.layer.borderColor = UIColor.lightGray.cgColor
        preview.layer.borderWidth = 1

        updatePreview(nil)
    }

    // MARK:- Private

    private var requestedTemplateItem: OUITemplateItem?
    private var thumbnailRequest: QLThumbnailGenerator.Request?

    private func updateThumbnail() {
        guard let preview = preview else { assertionFailure(); return }

        if let oldRequest = thumbnailRequest {
            if templateItem != requestedTemplateItem {
                QLThumbnailGenerator.shared.cancel(oldRequest)
                thumbnailRequest = nil
            } else {
                // Have a request and it is for the right template
                return
            }
        }

        guard let templateItem = templateItem else {
            updatePreview(nil)
            return
        }

        let fileURL = templateItem.fileURL
        let request = QLThumbnailGenerator.Request(fileAt: fileURL, size: preview.bounds.size, scale: UIScreen.main.scale, representationTypes: [.icon, .thumbnail])
        self.thumbnailRequest = request

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] (representation, error) in
            guard let self = self else { return }
            if let error = error {
                print("error making thumbnail for \(fileURL): \(error)")
            } else if let representation = representation {
                OperationQueue.main.addOperation { [weak self] in
                    guard let self = self else { return }
                    self.updatePreview(representation.uiImage)
                }
            }
            self.thumbnailRequest = nil
        }
    }

    private func updatePreview(_ previewImage: UIImage?) {
        guard let previewImage = previewImage else {
            preview.image = nil
            return
        }
        let imageSize = previewImage.size
        let isFullWidth = imageSize.width >= imageSize.height
        if isFullWidth {
            // Always turn off one constraint before turning on the other
            previewFullHeightConstraint.isActive = false
            previewFullWidthConstraint.isActive = true
        } else {
            // Always turn off one constraint before turning on the other
            previewFullWidthConstraint.isActive = false
            previewFullHeightConstraint.isActive = true
        }
        previewAspectRatio = imageSize.width / imageSize.height
        preview.image = previewImage
    }

}
