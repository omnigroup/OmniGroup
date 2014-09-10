// Copyright 2009-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUOpenGLExtensions.h"

#import <Foundation/Foundation.h>
#import <OmniBase/assertions.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

/* NOTE: It's essential that this list never, ever change, or else we won't be able to interpret the update information it sends back. If you need to make a change, create a new list with a new identifier (perhaps "2"). It's actually OK to *append* values to this list, but odds are that by the time we do that we'll want to re-sort the entries anyway. */
#define COMPACT_GL_EXTENSIONS_BITMAP_1_SIZE 124
#define COMPACT_GL_EXTENSIONS_BITMAP_1_IDENTIFIER "1"
static CFStringRef glExtensionsBitmap1[COMPACT_GL_EXTENSIONS_BITMAP_1_SIZE] = {
    CFSTR("GL_ARB_transpose_matrix"),
    CFSTR("GL_ARB_vertex_program"),
    CFSTR("GL_ARB_vertex_blend"),
    CFSTR("GL_ARB_window_pos"),
    CFSTR("GL_ARB_shader_objects"),
    CFSTR("GL_ARB_vertex_shader"),
    CFSTR("GL_ARB_shading_language_100"),
    CFSTR("GL_EXT_multi_draw_arrays"),
    CFSTR("GL_EXT_clip_volume_hint"),
    CFSTR("GL_EXT_rescale_normal"),
    CFSTR("GL_EXT_draw_range_elements"),
    CFSTR("GL_EXT_fog_coord"),
    CFSTR("GL_APPLE_client_storage"),
    CFSTR("GL_APPLE_specular_vector"),
    CFSTR("GL_APPLE_transform_hint"),
    CFSTR("GL_APPLE_packed_pixels"),
    CFSTR("GL_APPLE_fence"),
    CFSTR("GL_APPLE_vertex_array_object"),
    CFSTR("GL_APPLE_vertex_program_evaluators"),
    CFSTR("GL_APPLE_element_array"),
    CFSTR("GL_NV_texgen_reflection"),
    CFSTR("GL_NV_light_max_exponent"),
    CFSTR("GL_APPLE_flush_render"),
    CFSTR("GL_IBM_rasterpos_clip"),
    CFSTR("GL_SGIS_generate_mipmap"),
    CFSTR("GL_ARB_imaging"),
    CFSTR("GL_ARB_point_parameters"),
    CFSTR("GL_APPLE_ycbcr_422"),
    CFSTR("GL_ARB_multitexture"),
    CFSTR("GL_ARB_texture_env_add"),
    CFSTR("GL_ARB_texture_env_combine"),
    CFSTR("GL_EXT_texture_env_add"),
    CFSTR("GL_EXT_texture_lod_bias"),
    CFSTR("GL_EXT_bgra"),
    CFSTR("GL_EXT_abgr"),
    CFSTR("GL_EXT_secondary_color"),
    CFSTR("GL_SGIS_texture_edge_clamp"),
    CFSTR("GL_EXT_compiled_vertex_array"),
    CFSTR("GL_ARB_texture_cube_map"),
    CFSTR("GL_ARB_texture_env_dot3"),
    CFSTR("GL_ARB_texture_compression"),
    CFSTR("GL_ARB_texture_mirrored_repeat"),
    CFSTR("GL_EXT_texture_rectangle"),
    CFSTR("GL_EXT_texture_filter_anisotropic"),
    CFSTR("GL_EXT_texture_compression_s3tc"),
    CFSTR("GL_APPLE_texture_range"),
    CFSTR("GL_SGIS_texture_lod"),
    CFSTR("GL_EXT_stencil_wrap"),
    CFSTR("GL_NV_blend_square"),
    CFSTR("GL_ATI_texture_env_combine3"),
    CFSTR("GL_EXT_blend_color"),
    CFSTR("GL_EXT_blend_subtract"),
    CFSTR("GL_EXT_blend_minmax"),
    CFSTR("GL_APPLE_vertex_array_range"),
    CFSTR("GL_NV_fog_distance"),
    CFSTR("GL_NV_multisample_filter_hint"),
    CFSTR("GL_NV_register_combiners"),
    CFSTR("GL_ARB_texture_border_clamp"),
    CFSTR("GL_ARB_depth_texture"),
    CFSTR("GL_ARB_fragment_program"),
    CFSTR("GL_ARB_shadow"),
    CFSTR("GL_ARB_multisample"),
    CFSTR("GL_NV_depth_clamp"),
    CFSTR("GL_NV_point_sprite"),
    CFSTR("GL_NV_texture_shader"),
    CFSTR("GL_NV_register_combiners2"),
    CFSTR("GL_NV_texture_shader2"),
    CFSTR("GL_NV_texture_shader3"),
    CFSTR("GL_APPLE_pixel_buffer"),
    CFSTR("GL_EXT_shadow_funcs"),
    CFSTR("GL_EXT_stencil_two_side"),
    CFSTR("GL_ARB_texture_env_crossbar"),
    CFSTR("GL_ARB_vertex_buffer_object"),
    CFSTR("GL_EXT_blend_func_separate"),
    CFSTR("GL_ARB_fragment_shader"),
    CFSTR("GL_ARB_point_sprite"),
    CFSTR("GL_ARB_occlusion_query"),
    CFSTR("GL_ARB_texture_rectangle"),
    CFSTR("GL_EXT_texture_compression_dxt1"),
    CFSTR("GL_ARB_pixel_buffer_object"),
    CFSTR("GL_APPLE_float_pixels"),
    CFSTR("GL_EXT_framebuffer_object"),
    CFSTR("GL_NV_vertex_program2_option"),
    CFSTR("GL_NV_fragment_program_option"),
    CFSTR("GL_ATI_texture_float"),
    CFSTR("GL_NV_fragment_program2"),
    CFSTR("GL_NV_vertex_program3"),
    CFSTR("GL_EXT_gpu_program_parameters"),
    CFSTR("GL_APPLE_flush_buffer_range"),
    CFSTR("GL_EXT_packed_depth_stencil"),
    CFSTR("GL_ARB_fragment_program_shadow"),
    CFSTR("GL_ATI_separate_stencil"),
    CFSTR("GL_ARB_texture_float"),
    CFSTR("GL_ARB_shader_texture_lod"),
    CFSTR("GL_ARB_texture_non_power_of_two"),
    CFSTR("GL_EXT_blend_equation_separate"),
    CFSTR("GL_ARB_draw_buffers"),
    CFSTR("GL_ATI_texture_mirror_once"),
    CFSTR("GL_EXT_texture_mirror_clamp"),
    CFSTR("GL_EXT_geometry_shader4"),
    CFSTR("GL_EXT_transform_feedback"),
    CFSTR("GL_APPLE_aux_depth_stencil"),
    CFSTR("GL_APPLE_object_purgeable"),
    CFSTR("GL_EXT_texture_sRGB"),
    CFSTR("GL_ARB_half_float_pixel"),
    CFSTR("GL_EXT_depth_bounds_test"),
    CFSTR("GL_EXT_gpu_shader4"),
    CFSTR("GL_EXT_texture_integer"),
    CFSTR("GL_EXT_bindable_uniform"),
    CFSTR("GL_EXT_draw_buffers2"),
    CFSTR("GL_EXT_framebuffer_blit"),
    CFSTR("GL_EXT_framebuffer_multisample"),
    CFSTR("GL_EXT_separate_specular_color"),
    CFSTR("GL_SGI_color_matrix"),
    CFSTR("GL_ATI_blend_weighted_minmax"),
    CFSTR("GL_ATI_blend_equation_separate"),
    CFSTR("GL_ATI_texture_compression_3dc"),
    CFSTR("GL_ARB_shadow_ambient"),
    CFSTR("GL_ATI_text_fragment_shader"),
    CFSTR("GL_ATI_array_rev_comps_in_4_bytes"),
    CFSTR("GL_APPLE_rgb_422"),
    CFSTR("GL_ARB_half_float_vertex"),
    CFSTR("GL_EXT_framebuffer_sRGB"),
    CFSTR("GL_ARB_color_buffer_float"),
};

static void addToSet(const void *value, void *context)
{
    CFStringRef extensionName = (CFStringRef)value;
    if (CFStringGetLength(extensionName) > 0)
        CFSetAddValue((CFMutableSetRef)context, extensionName);
}

static void addToArray(const void *value, void *context)
{
    CFArrayAppendValue((CFMutableArrayRef)context, value);
}

static CFComparisonResult compareStrings(const void *v1, const void *v2, void *context)
{
    return CFStringCompare(v1, v2, kCFCompareNumerically);
}

static void append(const void *value, void *context)
{
    CFMutableStringRef buf = (CFMutableStringRef)context;
    CFStringAppend(buf, CFSTR(" "));
    CFStringAppend(buf, value);
}

#ifdef DEBUG
void OSULogTestGLExtensionCompressionTestVector(void)
{
    srandom((unsigned)time(NULL));
    NSMutableArray *extensions = [NSMutableArray array];
    unsigned extIndex;
    for (extIndex = 0; extIndex < COMPACT_GL_EXTENSIONS_BITMAP_1_SIZE; extIndex++) {
        if ((arc4random() % 8) == 0)
            [extensions addObject:(id)glExtensionsBitmap1[extIndex]];
    }
    
    NSString *extensionsString = [extensions componentsJoinedByString:@" "];
    CFStringRef compressed = OSUCopyCompactedOpenGLExtensionsList((CFStringRef)extensionsString);
    NSLog(@"extensionString %@", extensionsString);
    NSLog(@"compressed %@", compressed);
    CFRelease(compressed);
}

#endif

CFStringRef OSUCopyCompactedOpenGLExtensionsList(CFStringRef extList)
{
    if (!extList)
        return NULL;
    if (CFStringGetLength(extList) < 10) {
        return CFStringCreateCopy(kCFAllocatorDefault, extList);
    }
    
    CFMutableSetRef extensions;
    
    {
        CFArrayRef extensionsList = CFStringCreateArrayBySeparatingStrings(kCFAllocatorDefault, extList, CFSTR(" "));
        CFIndex numExts = CFArrayGetCount(extensionsList);
        extensions = CFSetCreateMutable(kCFAllocatorDefault, numExts, &kCFTypeSetCallBacks);
        CFArrayApplyFunction(extensionsList, (CFRange){0, numExts}, addToSet, extensions);
        CFRelease(extensionsList);
    }
    
    // Include extra zeroes at the end of the array to make the for() loop later simpler
    unsigned char *bits = malloc(COMPACT_GL_EXTENSIONS_BITMAP_1_SIZE + 4);
    memset(bits, 0, COMPACT_GL_EXTENSIONS_BITMAP_1_SIZE + 4);
    
    CFIndex firstUnusedIndex = 0;
    CFIndex bitsSet = 0;
    for(CFIndex extIndex = 0; extIndex < COMPACT_GL_EXTENSIONS_BITMAP_1_SIZE; extIndex ++) {
        CFStringRef extName = glExtensionsBitmap1[extIndex];
        if (CFSetContainsValue(extensions, extName)) {
            bits[extIndex] = 1;
            firstUnusedIndex = extIndex+1;
            bitsSet ++;
            CFSetRemoveValue(extensions, extName);
        }
    }
    
    CFMutableStringRef buf = CFStringCreateMutable(kCFAllocatorDefault, 0);
    CFStringAppend(buf, CFSTR(COMPACT_GL_EXTENSIONS_BITMAP_1_IDENTIFIER ","));
    for(CFIndex extIndex = 0; extIndex < firstUnusedIndex; extIndex += 4) {
        uint8_t nybble =
        ( bits[extIndex  ] ? 1 : 0 ) |
        ( bits[extIndex+1] ? 2 : 0 ) |
        ( bits[extIndex+2] ? 4 : 0 ) |
        ( bits[extIndex+3] ? 8 : 0 );
        char ch[2];
        ch[0] = "0123456789ABCDEF"[nybble];
        ch[1] = 0;
        CFStringAppendCString(buf, ch, kCFStringEncodingASCII);
    }
    
    free(bits);
    
    CFIndex leftoverCount = CFSetGetCount(extensions);
    if (leftoverCount) {
        CFMutableArrayRef leftoverValues = CFArrayCreateMutable(kCFAllocatorDefault, leftoverCount, &kCFTypeArrayCallBacks);
        CFSetApplyFunction(extensions, addToArray, leftoverValues);
        CFArraySortValues(leftoverValues, (CFRange){0, CFArrayGetCount(leftoverValues)}, compareStrings, NULL);
        CFArrayApplyFunction(leftoverValues, (CFRange){0, CFArrayGetCount(leftoverValues)}, append, buf);
        CFRelease(leftoverValues);
    }
    
    CFRelease(extensions);
   
#ifdef DEBUG
    {
        CFSetRef uA = OSUCopyParsedOpenGLExtensionsList(buf);
        CFSetRef uB = OSUCopyParsedOpenGLExtensionsList(extList);
        OBASSERT(CFEqual(uA, uB));
        CFRelease(uA);
        CFRelease(uB);
    }
#endif    
    
    if (CFStringGetLength(buf) < CFStringGetLength(extList)) {
        return buf;
    } else {
        CFRelease(buf);
        return CFStringCreateCopy(kCFAllocatorDefault, extList);
    }
}

static void unpackExtensionBitmap(CFMutableSetRef extensions, CFStringRef packed, unsigned int bitCount, CFStringRef *map)
{
    CFRange comma = CFStringFind(packed, CFSTR(","), 0);
    CFIndex firstNybble = comma.location + comma.length;
    unsigned long nybbleCount = CFStringGetLength(packed) - firstNybble;

    for(unsigned long nybbleIndex = 0; nybbleIndex < nybbleCount; nybbleIndex ++) {
        UniChar ch = CFStringGetCharacterAtIndex(packed, firstNybble+nybbleIndex);
        unsigned int value;
        for(value = 0; value < 16; value ++) {
            if (ch == (UniChar)("0123456789ABCDEF"[value]))
                break;
        }
        if (value >= 16) {
            OBASSERT_NOT_REACHED("invalid hex char");
            return;
        }
        if ((value & 1) && (0 + 4*nybbleIndex) < bitCount)
            CFSetAddValue(extensions, map[0 + 4*nybbleIndex]);
        if ((value & 2) && (1 + 4*nybbleIndex) < bitCount)
            CFSetAddValue(extensions, map[1 + 4*nybbleIndex]);
        if ((value & 4) && (2 + 4*nybbleIndex) < bitCount)
            CFSetAddValue(extensions, map[2 + 4*nybbleIndex]);
        if ((value & 8) && (3 + 4*nybbleIndex) < bitCount)
            CFSetAddValue(extensions, map[3 + 4*nybbleIndex]);
    }
}

CFSetRef OSUCopyParsedOpenGLExtensionsList(CFStringRef extList)
{
    CFMutableSetRef extensions = CFSetCreateMutable(kCFAllocatorDefault, 0, &kCFTypeSetCallBacks);
    
    CFArrayRef extensionsList = CFStringCreateArrayBySeparatingStrings(kCFAllocatorDefault, extList, CFSTR(" "));
    CFIndex numWords = CFArrayGetCount(extensionsList);

    for(CFIndex wordIndex = 0; wordIndex < numWords; wordIndex ++) {
        CFStringRef word = CFArrayGetValueAtIndex(extensionsList, wordIndex);
        if (CFStringGetLength(word) < 1)
            continue;
        
        if (CFStringHasPrefix(word, CFSTR(COMPACT_GL_EXTENSIONS_BITMAP_1_IDENTIFIER ","))) {
            unpackExtensionBitmap(extensions, word, COMPACT_GL_EXTENSIONS_BITMAP_1_SIZE, glExtensionsBitmap1);
        } else {
            CFSetAddValue(extensions, word);
        }
    }
    
    CFRelease(extensionsList);

    return extensions;
}

