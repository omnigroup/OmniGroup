// Copyright 2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$


extension OUIDocumentPickerViewController: OUITemplatePickerDelegate {

    @nonobjc public static func generalTemplates(in templatePicker: OUITemplatePicker) -> [OUITemplateItem] {
        var items = [OUITemplateItem]()
        if let templateChooser = OUIDocumentCreationTemplatePickerViewController(documentPicker: templatePicker.documentPicker, folderItem: templatePicker.folderItem, documentType: OUIDocumentPickerViewController.documentTypeForCurrentFilter(with: templatePicker.documentPicker)) {
            templateChooser.isReadOnly = true
            templateChooser.selectedFilterChanged()

            if let fileItems = templateChooser.sortedFilteredItems() {
                for fileItem in fileItems {
                    if let fileEdit = fileItem.fileEdit {
                        let templateItem = OUITemplateItem(fileURL: fileItem.fileURL, fileEdit: fileEdit, displayName: fileItem.name())
                        items.append(templateItem)
                    }
                }
            }
        }

        return items
    }

    public func templatePicker(_ templatePicker: OUITemplatePicker, didSelect templateURL: URL, animateFrom: UIView) {
        let context = OUINewDocumentCreationContext(with: selectedScope, store: documentStore, folderItem: folderItem, documentType: documentTypeForCurrentFilter(), templateURL: templateURL, animateFromView: animateFrom)
        newDocument(with: context, completion: nil)
    }

    public func generalTemplates(in templatePicker: OUITemplatePicker) -> [OUITemplateItem] {
        return OUIDocumentPickerViewController.generalTemplates(in: templatePicker)
    }

}
