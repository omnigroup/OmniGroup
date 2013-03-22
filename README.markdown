OmniGroup
===========

Checking out the source
-----------------------

    git clone git://github.com/omnigroup/OmniGroup
    git submodule init
    git submodule update

Configuring Xcode 4
-------------------

- We currently use Xcode 4.6.1. You'll probably have the best results if you do too.
- Add the projects you want to your workspace
- If building for iOS, you need to edit your scheme to turn off implicit dependencies and parallel builds. Xcode 4 doesn't understand implicit dependencies with static libraries, so you'll need to add the dependencies to your scheme in the right order.
- Take a look in the Workspaces directory for a sample workspace for the TextEditor iPad example app.

Supported Targets
----------------------

- We require iOS 6 and Mac OS X 10.7, _but_ several bits of framework code implicitly require 10.8 for auto-layout or layer-backing fixes, or explicitly require them for things like `NSXPCConnection`.

Configuring the Source
----------------------

We place our project-wide configuration options in xcconfig files, under `OmniGroup/Configurations`. The naming scheme of the files is fairly straightforward, hopefully. Each project has `Omni-Global-{Debug,Release,...}.xcconfig` as the basis for the corresponding configuration. Each Mac target has `Omni-{Bundle,Application,Tool,...}-{Debug,Release,...}.xcconfig` and each iOS target has `Touch-{Application,Library}-{Debug,Release,...}.xcconfig`. Each of these end point configurations when `#include`s 'superclass' configurations (with "Common" in the name).

 
Building from the command line
------------------------------

To build Debug versions of all the Omni frameworks:

    cd OmniGroup
    ./Scripts/Build Frameworks

To build Release versions of all the Omni frameworks, instead do:

    ./Scripts/Build Frameworks install

Enjoy!
