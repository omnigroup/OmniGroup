OmniGroup
===========

Checking out the source
-----------------------

git clone git://github.com/omnigroup/OmniGroup

Configuring Xcode 4
-------------------

- Add the projects you want to your workspace
- If building for iOS, you need to edit your scheme to turn off implicit dependencies and parallel builds. Xcode 4 doesn't understand implicit dependencies with static libraries, so you'll need to add the dependencies to your scheme in the right order.
- Take a look in the Workspaces directory for a sample workspace for the TextEditor iPad example app.

Configuring Xcode 3
-------------------

Xcode or later 3.2.5 + iOS 4.2 is required (though the frameworks target a minimum of iOS 3.2 currently).

The source is set up assuming a customized build products directory since that is what we do at Omni.

- Open Xcode's Building preferences pane
- Select "Customized location" for the "Place Build Products in:" option
- Enter a convenient path like /Users/Shared/your-login/Products

Configuring the Source
----------------------

We place our project-wide configuration options in xcconfig files, under OmniGroup/Configurations. The naming scheme of the files is fairly straightforward, hopefully. Each project has Omni-Global-{Debug,Release,...}.xconfig as the basis for the corresponding configuration. Each Mac target has Omni-{Bundle,Application,Tool,...}-{Debug,Release,...}.xconfig and each iOS target has Touch-{Application,Library}-{Debug,Release,...}.xcconfig. Each of these end point configurations when #includes 'superclass' configurations (with "Common" in the name).

Building for Xcode 4
--------------------

For debug builds, just build in a workspace as above. We don't yet do production builds with Xcode 4, so this is a bit of a gray area still.
The most likely issues are setting up the `@executable_path` support for Mac frameworks and code signing for iOS. Give it a whirl and send a patch!
 
Building for Xcode 3
--------------------

To build Debug versions of all the Omni frameworks:

    cd OmniGroup
    ./Scripts/Build Frameworks

To build Release versions of all the Omni frameworks, instead do:

    ./Scripts/Build Frameworks install

Enjoy!
