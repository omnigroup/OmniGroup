OmniGroup
===========

Checking out the source
-----------------------

git clone git://github.com/omnigroup/OmniGroup

Configuring Xcode
-----------------

Xcode or later 3.2.5 + iOS 4.2 is required (though the frameworks target a minimum of iOS 3.2 currently).

The source is set up assuming a customized build products directory since that is what we do at Omni.

- Open Xcode's Building preferences pane
- Select "Customized location" for the "Place Build Products in:" option
- Enter a convenient path like /Users/Shared/your-login/Products

Configuring the Source
----------------------

We place our project-wide configuration options in xcconfig files, under OmniGroup/Configurations. The naming scheme of the files is fairly straightforward, hopefully. Each project has Omni-Global-{Debug,Release,...}.xconfig as the basis for the corresponding configuration. Each Mac target has Omni-{Bundle,Application,Tool,...}-{Debug,Release,...}.xconfig and each iOS target has Touch-{Application,Library}-{Debug,Release,...}.xcconfig. Each of these end point configurations when #includes 'superclass' configurations (with "Common" in the name).

Building
--------

To build Debug versions of all the Omni frameworks:

    cd OmniGroup
    ./Scripts/Build Frameworks

To build Release versions of all the Omni frameworks, instead do:

    ./Scripts/Build Frameworks install

Enjoy!
