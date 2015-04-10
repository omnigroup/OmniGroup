// Copyright 2009-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUOpenGLExtensions.h"

#import <Foundation/Foundation.h>
#import <OmniBase/assertions.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/macros.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC

/* NOTE: It's essential that these lists never, ever change, or else we won't be able to interpret the update information it sends back. If you need to make a change, create a new list with a new identifier. It's actually OK to *append* values to this list, but odds are that by the time we do that we'll want to re-sort the entries anyway. */

typedef struct _OSUExtensionsBitmap {
    __unsafe_unretained NSString *prefix;
    __unsafe_unretained NSString *names[];
} OSUExtensionsBitmap;

#define NSSTR(x) @x

static const OSUExtensionsBitmap OSUExtensionsBitmap_GL_v1 = {
    .prefix = @"1,",
    .names = {
        NSSTR("GL_ARB_transpose_matrix"),
        NSSTR("GL_ARB_vertex_program"),
        NSSTR("GL_ARB_vertex_blend"),
        NSSTR("GL_ARB_window_pos"),
        NSSTR("GL_ARB_shader_objects"),
        NSSTR("GL_ARB_vertex_shader"),
        NSSTR("GL_ARB_shading_language_100"),
        NSSTR("GL_EXT_multi_draw_arrays"),
        NSSTR("GL_EXT_clip_volume_hint"),
        NSSTR("GL_EXT_rescale_normal"),
        NSSTR("GL_EXT_draw_range_elements"),
        NSSTR("GL_EXT_fog_coord"),
        NSSTR("GL_APPLE_client_storage"),
        NSSTR("GL_APPLE_specular_vector"),
        NSSTR("GL_APPLE_transform_hint"),
        NSSTR("GL_APPLE_packed_pixels"),
        NSSTR("GL_APPLE_fence"),
        NSSTR("GL_APPLE_vertex_array_object"),
        NSSTR("GL_APPLE_vertex_program_evaluators"),
        NSSTR("GL_APPLE_element_array"),
        NSSTR("GL_NV_texgen_reflection"),
        NSSTR("GL_NV_light_max_exponent"),
        NSSTR("GL_APPLE_flush_render"),
        NSSTR("GL_IBM_rasterpos_clip"),
        NSSTR("GL_SGIS_generate_mipmap"),
        NSSTR("GL_ARB_imaging"),
        NSSTR("GL_ARB_point_parameters"),
        NSSTR("GL_APPLE_ycbcr_422"),
        NSSTR("GL_ARB_multitexture"),
        NSSTR("GL_ARB_texture_env_add"),
        NSSTR("GL_ARB_texture_env_combine"),
        NSSTR("GL_EXT_texture_env_add"),
        NSSTR("GL_EXT_texture_lod_bias"),
        NSSTR("GL_EXT_bgra"),
        NSSTR("GL_EXT_abgr"),
        NSSTR("GL_EXT_secondary_color"),
        NSSTR("GL_SGIS_texture_edge_clamp"),
        NSSTR("GL_EXT_compiled_vertex_array"),
        NSSTR("GL_ARB_texture_cube_map"),
        NSSTR("GL_ARB_texture_env_dot3"),
        NSSTR("GL_ARB_texture_compression"),
        NSSTR("GL_ARB_texture_mirrored_repeat"),
        NSSTR("GL_EXT_texture_rectangle"),
        NSSTR("GL_EXT_texture_filter_anisotropic"),
        NSSTR("GL_EXT_texture_compression_s3tc"),
        NSSTR("GL_APPLE_texture_range"),
        NSSTR("GL_SGIS_texture_lod"),
        NSSTR("GL_EXT_stencil_wrap"),
        NSSTR("GL_NV_blend_square"),
        NSSTR("GL_ATI_texture_env_combine3"),
        NSSTR("GL_EXT_blend_color"),
        NSSTR("GL_EXT_blend_subtract"),
        NSSTR("GL_EXT_blend_minmax"),
        NSSTR("GL_APPLE_vertex_array_range"),
        NSSTR("GL_NV_fog_distance"),
        NSSTR("GL_NV_multisample_filter_hint"),
        NSSTR("GL_NV_register_combiners"),
        NSSTR("GL_ARB_texture_border_clamp"),
        NSSTR("GL_ARB_depth_texture"),
        NSSTR("GL_ARB_fragment_program"),
        NSSTR("GL_ARB_shadow"),
        NSSTR("GL_ARB_multisample"),
        NSSTR("GL_NV_depth_clamp"),
        NSSTR("GL_NV_point_sprite"),
        NSSTR("GL_NV_texture_shader"),
        NSSTR("GL_NV_register_combiners2"),
        NSSTR("GL_NV_texture_shader2"),
        NSSTR("GL_NV_texture_shader3"),
        NSSTR("GL_APPLE_pixel_buffer"),
        NSSTR("GL_EXT_shadow_funcs"),
        NSSTR("GL_EXT_stencil_two_side"),
        NSSTR("GL_ARB_texture_env_crossbar"),
        NSSTR("GL_ARB_vertex_buffer_object"),
        NSSTR("GL_EXT_blend_func_separate"),
        NSSTR("GL_ARB_fragment_shader"),
        NSSTR("GL_ARB_point_sprite"),
        NSSTR("GL_ARB_occlusion_query"),
        NSSTR("GL_ARB_texture_rectangle"),
        NSSTR("GL_EXT_texture_compression_dxt1"),
        NSSTR("GL_ARB_pixel_buffer_object"),
        NSSTR("GL_APPLE_float_pixels"),
        NSSTR("GL_EXT_framebuffer_object"),
        NSSTR("GL_NV_vertex_program2_option"),
        NSSTR("GL_NV_fragment_program_option"),
        NSSTR("GL_ATI_texture_float"),
        NSSTR("GL_NV_fragment_program2"),
        NSSTR("GL_NV_vertex_program3"),
        NSSTR("GL_EXT_gpu_program_parameters"),
        NSSTR("GL_APPLE_flush_buffer_range"),
        NSSTR("GL_EXT_packed_depth_stencil"),
        NSSTR("GL_ARB_fragment_program_shadow"),
        NSSTR("GL_ATI_separate_stencil"),
        NSSTR("GL_ARB_texture_float"),
        NSSTR("GL_ARB_shader_texture_lod"),
        NSSTR("GL_ARB_texture_non_power_of_two"),
        NSSTR("GL_EXT_blend_equation_separate"),
        NSSTR("GL_ARB_draw_buffers"),
        NSSTR("GL_ATI_texture_mirror_once"),
        NSSTR("GL_EXT_texture_mirror_clamp"),
        NSSTR("GL_EXT_geometry_shader4"),
        NSSTR("GL_EXT_transform_feedback"),
        NSSTR("GL_APPLE_aux_depth_stencil"),
        NSSTR("GL_APPLE_object_purgeable"),
        NSSTR("GL_EXT_texture_sRGB"),
        NSSTR("GL_ARB_half_float_pixel"),
        NSSTR("GL_EXT_depth_bounds_test"),
        NSSTR("GL_EXT_gpu_shader4"),
        NSSTR("GL_EXT_texture_integer"),
        NSSTR("GL_EXT_bindable_uniform"),
        NSSTR("GL_EXT_draw_buffers2"),
        NSSTR("GL_EXT_framebuffer_blit"),
        NSSTR("GL_EXT_framebuffer_multisample"),
        NSSTR("GL_EXT_separate_specular_color"),
        NSSTR("GL_SGI_color_matrix"),
        NSSTR("GL_ATI_blend_weighted_minmax"),
        NSSTR("GL_ATI_blend_equation_separate"),
        NSSTR("GL_ATI_texture_compression_3dc"),
        NSSTR("GL_ARB_shadow_ambient"),
        NSSTR("GL_ATI_text_fragment_shader"),
        NSSTR("GL_ATI_array_rev_comps_in_4_bytes"),
        NSSTR("GL_APPLE_rgb_422"),
        NSSTR("GL_ARB_half_float_vertex"),
        NSSTR("GL_EXT_framebuffer_sRGB"),
        NSSTR("GL_ARB_color_buffer_float"),
        NULL,
    }
};

static const OSUExtensionsBitmap OSUExtensionsBitmap_GL_v2 = {
    .prefix = @"2,",
    .names = {
        NSSTR("GL_ARB_multitexture"), // 282841
        NSSTR("GL_ARB_shader_objects"), // 282840
        NSSTR("GL_EXT_rescale_normal"), // 282838
        NSSTR("GL_ARB_window_pos"), // 282838
        NSSTR("GL_ARB_transpose_matrix"), // 282838
        NSSTR("GL_ARB_vertex_shader"), // 282838
        NSSTR("GL_ARB_vertex_program"), // 282838
        NSSTR("GL_APPLE_vertex_program_evaluators"), // 282838
        NSSTR("GL_EXT_clip_volume_hint"), // 282838
        NSSTR("GL_ARB_vertex_blend"), // 282838
        NSSTR("GL_APPLE_element_array"), // 282838
        NSSTR("GL_EXT_fog_coord"), // 282838
        NSSTR("GL_APPLE_client_storage"), // 282838
        NSSTR("GL_APPLE_specular_vector"), // 282838
        NSSTR("GL_APPLE_transform_hint"), // 282838
        NSSTR("GL_APPLE_packed_pixels"), // 282838
        NSSTR("GL_APPLE_fence"), // 282838
        NSSTR("GL_APPLE_vertex_array_object"), // 282838
        NSSTR("GL_APPLE_flush_render"), // 282838
        NSSTR("GL_NV_texgen_reflection"), // 282837
        NSSTR("GL_ARB_texture_env_add"), // 282836
        NSSTR("GL_EXT_draw_range_elements"), // 282836
        NSSTR("GL_IBM_rasterpos_clip"), // 282836
        NSSTR("GL_EXT_secondary_color"), // 282835
        NSSTR("GL_SGIS_generate_mipmap"), // 282835
        NSSTR("GL_APPLE_pixel_buffer"), // 282835
        NSSTR("GL_EXT_abgr"), // 282835
        NSSTR("GL_EXT_bgra"), // 282835
        NSSTR("GL_EXT_texture_lod_bias"), // 282835
        NSSTR("GL_NV_light_max_exponent"), // 282835
        NSSTR("GL_ARB_texture_env_combine"), // 282835
        NSSTR("GL_EXT_texture_env_add"), // 282835
        NSSTR("GL_EXT_multi_draw_arrays"), // 282834
        NSSTR("GL_SGIS_texture_edge_clamp"), // 282834
        NSSTR("GL_ARB_texture_compression"), // 282834
        NSSTR("GL_ARB_texture_cube_map"), // 282834
        NSSTR("GL_ARB_texture_mirrored_repeat"), // 282833
        NSSTR("GL_ARB_pixel_buffer_object"), // 282833
        NSSTR("GL_ARB_vertex_buffer_object"), // 282832
        NSSTR("GL_EXT_texture_rectangle"), // 282832
        NSSTR("GL_EXT_texture_filter_anisotropic"), // 282832
        NSSTR("GL_APPLE_texture_range"), // 282831
        NSSTR("GL_EXT_stencil_wrap"), // 282830
        NSSTR("GL_EXT_texture_compression_s3tc"), // 282830
        NSSTR("GL_ARB_texture_rectangle"), // 282829
        NSSTR("GL_EXT_blend_minmax"), // 282829
        NSSTR("GL_EXT_blend_subtract"), // 282829
        NSSTR("GL_NV_blend_square"), // 282829
        NSSTR("GL_EXT_blend_color"), // 282829
        NSSTR("GL_SGIS_texture_lod"), // 282828
        NSSTR("GL_ARB_shading_language_100"), // 282827
        NSSTR("GL_APPLE_ycbcr_422"), // 282826
        NSSTR("GL_ARB_texture_env_dot3"), // 282824
        NSSTR("GL_ATI_texture_env_combine3"), // 282822
        NSSTR("GL_EXT_texture_compression_dxt1"), // 282820
        NSSTR("GL_ARB_texture_border_clamp"), // 282819
        NSSTR("GL_EXT_blend_func_separate"), // 282815
        NSSTR("GL_ARB_fragment_shader"), // 282794
        NSSTR("GL_ARB_depth_texture"), // 282793
        NSSTR("GL_ARB_fragment_program"), // 282793
        NSSTR("GL_ARB_point_sprite"), // 282791
        NSSTR("GL_EXT_framebuffer_object"), // 282785
        NSSTR("GL_ARB_shadow"), // 282780
        NSSTR("GL_EXT_shadow_funcs"), // 282780
        NSSTR("GL_EXT_blend_equation_separate"), // 282576
        NSSTR("GL_EXT_stencil_two_side"), // 282504
        NSSTR("GL_APPLE_flush_buffer_range"), // 282431
        NSSTR("GL_EXT_gpu_program_parameters"), // 282429
        NSSTR("GL_EXT_packed_depth_stencil"), // 282399
        NSSTR("GL_ARB_texture_non_power_of_two"), // 282374
        NSSTR("GL_APPLE_vertex_array_range"), // 282110
        NSSTR("GL_ARB_texture_env_crossbar"), // 281970
        NSSTR("GL_ARB_point_parameters"), // 281890
        NSSTR("GL_ARB_fragment_program_shadow"), // 281704
        NSSTR("GL_ATI_separate_stencil"), // 281669
        NSSTR("GL_ARB_occlusion_query"), // 281089
        NSSTR("GL_NV_fog_distance"), // 281044
        NSSTR("GL_APPLE_aux_depth_stencil"), // 280842
        NSSTR("GL_APPLE_object_purgeable"), // 280823
        NSSTR("GL_APPLE_float_pixels"), // 280809
        NSSTR("GL_ATI_texture_float"), // 280805
        NSSTR("GL_ARB_multisample"), // 280732
        NSSTR("GL_EXT_texture_sRGB"), // 280665
        NSSTR("GL_EXT_geometry_shader4"), // 280652
        NSSTR("GL_ARB_draw_buffers"), // 280647
        NSSTR("GL_EXT_transform_feedback"), // 280642
        NSSTR("GL_ARB_texture_float"), // 280438
        NSSTR("GL_ARB_shader_texture_lod"), // 280098
        NSSTR("GL_EXT_separate_specular_color"), // 279957
        NSSTR("GL_APPLE_rgb_422"), // 279804
        NSSTR("GL_ATI_texture_mirror_once"), // 279649
        NSSTR("GL_ARB_half_float_pixel"), // 279560
        NSSTR("GL_EXT_provoking_vertex"), // 279439
        NSSTR("GL_EXT_framebuffer_blit"), // 278997
        NSSTR("GL_ARB_half_float_vertex"), // 278760
        NSSTR("GL_ARB_instanced_arrays"), // 278721
        NSSTR("GL_EXT_framebuffer_multisample"), // 278642
        NSSTR("GL_ARB_texture_rg"), // 278302
        NSSTR("GL_EXT_vertex_array_bgra"), // 278130
        NSSTR("GL_EXT_framebuffer_sRGB"), // 277894
        NSSTR("GL_NV_depth_clamp"), // 277116
        NSSTR("GL_EXT_draw_buffers2"), // 276998
        NSSTR("GL_ARB_color_buffer_float"), // 276846
        NSSTR("GL_ARB_framebuffer_object"), // 276840
        NSSTR("GL_ARB_texture_compression_rgtc"), // 276838
        NSSTR("GL_ARB_depth_buffer_float"), // 276837
        NSSTR("GL_EXT_gpu_shader4"), // 276786
        NSSTR("GL_EXT_texture_integer"), // 276769
        NSSTR("GL_EXT_texture_array"), // 276564
        NSSTR("GL_EXT_packed_float"), // 276553
        NSSTR("GL_NV_conditional_render"), // 276364
        NSSTR("GL_EXT_texture_shared_exponent"), // 276276
        NSSTR("GL_ARB_draw_elements_base_vertex"), // 275560
        NSSTR("GL_ARB_sync"), // 275556
        NSSTR("GL_APPLE_row_bytes"), // 275553
        NSSTR("GL_ARB_provoking_vertex"), // 275342
        NSSTR("GL_ARB_vertex_array_bgra"), // 275309
        NSSTR("GL_APPLE_vertex_point_size"), // 275282
        NSSTR("GL_ARB_depth_clamp"), // 275053
        NSSTR("GL_ARB_draw_instanced"), // 274939
        NSSTR("GL_ARB_framebuffer_sRGB"), // 274913
        NSSTR("GL_EXT_texture_sRGB_decode"), // 274528
        NSSTR("GL_EXT_timer_query"), // 274285
        NSSTR("GL_ARB_seamless_cube_map"), // 270416
        NSSTR("GL_EXT_debug_label"), // 270379
        NSSTR("GL_EXT_debug_marker"), // 270372
        NSSTR("GL_NV_texture_barrier"), // 269762
        NSSTR("GL_EXT_framebuffer_multisample_blit_scaled"), // 201047
        NSSTR("GL_ARB_imaging"), // 127026
        NSSTR("GL_EXT_texture_mirror_clamp"), // 126747
        NSSTR("GL_EXT_bindable_uniform"), // 123179
        NSSTR("GL_EXT_depth_bounds_test"), // 90644
        NSSTR("GL_NV_multisample_filter_hint"), // 85808
        NSSTR("GL_NV_point_sprite"), // 85794
        NSSTR("GL_NV_fragment_program_option"), // 85792
        NSSTR("GL_NV_vertex_program2_option"), // 85789
        NSSTR("GL_NV_fragment_program2"), // 85673
        NSSTR("GL_NV_vertex_program3"), // 85673
        NSSTR("GL_SGI_color_matrix"), // 41219
        NSSTR("GL_ATI_blend_weighted_minmax"), // 41217
        NSSTR("GL_ATI_blend_equation_separate"), // 41217
        NSSTR("GL_ARB_shadow_ambient"), // 41182
        NSSTR("GL_ATI_texture_compression_3dc"), // 40914
        NSSTR("GL_EXT_compiled_vertex_array"), // 15721
        NSSTR("GL_ATI_text_fragment_shader"), // 1302
        NSSTR("GL_NV_register_combiners"), // 592
        NSSTR("GL_NV_texture_shader"), // 578
        NSSTR("GL_NV_texture_shader3"), // 577
        NSSTR("GL_NV_texture_shader2"), // 577
        NSSTR("GL_NV_register_combiners2"), // 577
        NULL,
    }
};

static const OSUExtensionsBitmap OSUExtensionsBitmap_CL_v1 = {
    .prefix = @"3,",
    .names = {
        NSSTR("cl_APPLE_SetMemObjectDestructor"), // 315244
        NSSTR("cl_APPLE_ContextLoggingFunctions"), // 315218
        NSSTR("cl_APPLE_clut"), // 315217
        NSSTR("cl_APPLE_query_kernel_names"), // 315217
        NSSTR("cl_APPLE_gl_sharing"), // 315217
        NSSTR("cl_khr_gl_event"), // 291200
        NSSTR("cl_khr_gl_event%00"), // 24017
        NULL,
    }
};

static const OSUExtensionsBitmap *OSUExtensionsBitmaps[] = {
    &OSUExtensionsBitmap_GL_v1,
    &OSUExtensionsBitmap_GL_v2,
    &OSUExtensionsBitmap_CL_v1,
    NULL,
};

#ifdef OMNI_ASSERTIONS_ON
static void _OSUCheckExtensionBitmapPrefixes(void) __attribute__((constructor));
static void _OSUCheckExtensionBitmapPrefixes(void)
{
    NSMutableSet *prefixes = [[NSMutableSet alloc] init];
    
    const OSUExtensionsBitmap *bitmap;
    for (NSUInteger bitmapIndex = 0; (bitmap = OSUExtensionsBitmaps[bitmapIndex]); bitmapIndex++) {
        OBASSERT([bitmap->prefix hasSuffix:@","], "OSU extension bitmap prefix must end in a comma");
        OBASSERT([prefixes member:bitmap->prefix] == nil, "OSU extension bitmap prefix \"%@\" is duplicated", bitmap->prefix);
        [prefixes addObject:bitmap->prefix];
    }
}
#endif

static NSUInteger extensionBitmapNameCount(const OSUExtensionsBitmap *bitmap)
{
    NSUInteger count = 0;
    
    while (bitmap->names[count])
        count++;
    return count;
}

#ifdef DEBUG
void OSULogTestGLExtensionCompressionTestVector(void)
{
    const OSUExtensionsBitmap *bitmap = &OSUExtensionsBitmap_GL_v1;

    srandom((unsigned)time(NULL));
    NSMutableArray *extensions = [NSMutableArray array];
    
    for (unsigned long extIndex = 0; bitmap->names[extIndex]; extIndex++) {
        if ((arc4random() % 8) == 0)
            [extensions addObject:(id)bitmap->names[extIndex]];
    }
    
    NSString *extensionsString = [extensions componentsJoinedByString:@" "];
    NSString *compressed = OSUCopyCompactedOpenGLExtensionsList(extensionsString);
    OBASSERT([compressed hasSuffix:@"0"] == NO, "Unused nybbles at the end should not be emitted");
    
    NSLog(@"extensionString %@", extensionsString);
    NSLog(@"compressed %@", compressed);
}
#endif

static NSString *_OSUCopyCompactedOpenGLExtensionsList(const OSUExtensionsBitmap *bitmap, NSString *extList) NS_RETURNS_RETAINED;
static NSString *_OSUCopyCompactedOpenGLExtensionsList(const OSUExtensionsBitmap *bitmap, NSString *extList)
{
    if (!extList)
        return nil;
    
    NSMutableSet *extensions = [[NSMutableSet alloc] initWithArray:[extList componentsSeparatedByString:@" "]];
    [extensions removeObject:@""]; // In case there is a trailing space in the source or double spaces somewhere in it.
    
    NSMutableIndexSet *bits = [[NSMutableIndexSet alloc] init];
    
    NSUInteger firstUnusedIndex = 0;
    NSUInteger bitsSet = 0;
    NSString *extName;
    for (NSUInteger extIndex = 0; (extName = bitmap->names[extIndex]); extIndex ++) {
        if ([extensions member:(id)extName]) {
            [bits addIndex:extIndex];
            firstUnusedIndex = extIndex+1;
            bitsSet ++;
            [extensions removeObject:(id)extName];
        }
    }
    
    OBASSERT([bitmap->prefix hasSuffix:@","]);
    NSMutableString *buf = [[NSMutableString alloc] initWithString:bitmap->prefix];
    
    for (NSUInteger extIndex = 0; extIndex < firstUnusedIndex; extIndex += 4) {
        uint8_t nybble =
        ( [bits containsIndex:extIndex + 0] ? 1 : 0 ) |
        ( [bits containsIndex:extIndex + 1] ? 2 : 0 ) |
        ( [bits containsIndex:extIndex + 2] ? 4 : 0 ) |
        ( [bits containsIndex:extIndex + 3] ? 8 : 0 );
        char ch = "0123456789ABCDEF"[nybble];
        [buf appendFormat:@"%c", ch];
    }
    
    if ([extensions count] > 0) {
        NSArray *leftoverValues = [[extensions allObjects] sortedArrayUsingComparator:^NSComparisonResult(NSString *ext1, NSString *ext2) {
            return [ext1 compare:ext2 options:NSNumericSearch];
        }];
        for (NSString *ext in leftoverValues) {
            [buf appendString:@" "];
            [buf appendString:ext];
        }
    }
    
#ifdef DEBUG
    {
        NSSet *uA = OSUCopyParsedOpenGLExtensionsList(buf);
        NSSet *uB = OSUCopyParsedOpenGLExtensionsList(extList);
        OBASSERT([uA isEqual:uB]);
    }
#endif
    
    return buf;
}

NSString *OSUCopyCompactedOpenGLExtensionsList(NSString *extList)
{
    const OSUExtensionsBitmap *bitmap;
    
    NSString *best = [extList copy];
    
    for (NSUInteger bitmapIndex = 0; (bitmap = OSUExtensionsBitmaps[bitmapIndex]); bitmapIndex++) {
        NSString *try = _OSUCopyCompactedOpenGLExtensionsList(bitmap, extList);
        if ([try length] < [best length]) {
            best = [try copy];
        }
    }
    
    return best;
}

static void unpackExtensionBitmap(NSMutableSet *extensions, NSString *packed, const OSUExtensionsBitmap *bitmap)
{
    NSUInteger nybbleCount = [packed length];

    NSUInteger bitCount = extensionBitmapNameCount(bitmap);
    
    for (NSUInteger nybbleIndex = 0; nybbleIndex < nybbleCount; nybbleIndex ++) {
        UniChar ch = [packed characterAtIndex:nybbleIndex];
        unsigned int value;
        for (value = 0; value < 16; value ++) {
            if (ch == (UniChar)("0123456789ABCDEF"[value]))
                break;
        }
        if (value >= 16) {
            OBASSERT_NOT_REACHED("invalid hex char");
            return;
        }
        if ((value & 1) && (0 + 4*nybbleIndex) < bitCount)
            [extensions addObject:(id)bitmap->names[0 + 4*nybbleIndex]];
        if ((value & 2) && (1 + 4*nybbleIndex) < bitCount)
            [extensions addObject:(id)bitmap->names[1 + 4*nybbleIndex]];
        if ((value & 4) && (2 + 4*nybbleIndex) < bitCount)
            [extensions addObject:(id)bitmap->names[2 + 4*nybbleIndex]];
        if ((value & 8) && (3 + 4*nybbleIndex) < bitCount)
            [extensions addObject:(id)bitmap->names[3 + 4*nybbleIndex]];
    }
}

NSSet *OSUCopyParsedOpenGLExtensionsList(NSString *extList)
{
    NSMutableSet *extensions = [[NSMutableSet alloc] init];
    
    NSArray *extensionsList = [extList componentsSeparatedByString:@" "];
    for (NSString *word in extensionsList) {
        if ([word length] < 1)
            continue;

        const OSUExtensionsBitmap *bitmap;
        for (NSUInteger bitmapIndex = 0; (bitmap = OSUExtensionsBitmaps[bitmapIndex]); bitmapIndex++) {
            if ([word hasPrefix:bitmap->prefix])
                break;
        }
        if (bitmap) {
            unpackExtensionBitmap(extensions, [word substringFromIndex:[bitmap->prefix length]], bitmap);
        } else {
            [extensions addObject:word];
        }
    }
    
    return extensions;
}

