OmniGroup
===========

Checking out the source
-----------------------

git clone git://github.com/omnigroup/OmniGroup

Configuring Xcode
------------------

The source is set up assuming a customized build products directory since that is what we do at Omni.

- Open Xcode's Building preferences pane
- Select "Customized location" for the "Place Build Products in:" option
- Enter a convenient path like /Users/Shared/your-login/Products

Building
--------

To build Debug versions of all the Omni frameworks:

    cd OmniGroup
    ./Scripts/Build Frameworks

To build Release versions of all the Omni frameworks, instead do:

    ./Scripts/Build Frameworks install

Enjoy!
