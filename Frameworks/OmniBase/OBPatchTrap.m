// Copyright 2010-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OBPatchTrap.h"
#import <OmniBase/rcsid.h>

#import <dlfcn.h>
#include <mach/mach_vm.h>
#include <mach/mach_error.h>
#include <mach/mach_port.h>
#include <libkern/OSCacheControl.h>

#ifdef DEBUG

RCS_ID("$Id$")

BOOL OBPatchCode(void *address, size_t size, const void *newvalue)
{
    kern_return_t krt;
    
    task_t task = mach_task_self();
    mach_vm_address_t region_start = (uintptr_t)address;
    mach_vm_size_t region_size = size;
    vm_region_submap_short_info_data_64_t submap_info;
    mach_msg_type_number_t submap_info_count = VM_REGION_SUBMAP_SHORT_INFO_COUNT_64;
    natural_t region_depth = 1000;
    
    /* We want to use mach_vm_region_recurse() here rather than mach_vm_region, in order to get the innermost member of any submap. */
    
    krt = mach_vm_region_recurse(task, &region_start, &region_size, &region_depth, (void *)&submap_info, &submap_info_count);
    if (krt != KERN_SUCCESS) {
        printf("mach_vm_region_recurse(0x%llx): %s\n", (unsigned long long)(uintptr_t)address, mach_error_string(krt));
        return NO;
    } else {
        printf("mach_vm_region_recurse -> 0x%llx 0x%llx; prot=0x%04x, depth=%d\n", (unsigned long long)region_start, (unsigned long long)region_size, submap_info.protection, region_depth);
    }
    
    vm_prot_t current_prot = submap_info.protection;
    vm_prot_t new_prot = current_prot | ( VM_PROT_WRITE );
    
    if (current_prot & VM_PROT_WRITE) {
        /* hey, no problem! */
        memcpy(address, newvalue, size);
        return YES;
    }
    
    krt = mach_vm_protect(task, region_start, region_size, 0, new_prot | (region_depth > 0 ? VM_PROT_COPY : 0 ));
    if (krt != KERN_SUCCESS) {
        printf("mach_vm_protect(0x%llx, 0x%04x): %s\n", (unsigned long long)region_start, (unsigned)new_prot, mach_error_string(krt));
        return NO;
    }
    
    memcpy(address, newvalue, size);
    
    krt = mach_vm_protect(task, region_start, region_size, 0, current_prot);
    if (krt != KERN_SUCCESS) {
        printf("mach_vm_protect(0x%llx, 0x%04x): %s\n", (unsigned long long)region_start, (unsigned)current_prot, mach_error_string(krt));
    }
    
    sys_icache_invalidate(address, size);
    
    return YES;
}

BOOL OBPatchStretToNil(void (*callme)(void *, id, SEL, ...))
{
#if defined(__x86_64__)
    void *stret = dlsym(RTLD_DEFAULT, "objc_msgSend_stret");
    
    if (stret) {
        void *dest = NULL;
        static const unsigned char prologue[5] = {
            0x48, 0x85, 0xf6,   /* test %rsi, %rsi */
            0x0f, 0x84,         /* jump near if equal (32-bit displacement) */
        };
        static const unsigned char prologue2[4] = {
            0x48, 0x85, 0xf6,   /* test %rsi, %rsi */
            0x74,               /* jump near if equal (8-bit displacement) */
        };
        if (memcmp(stret, prologue, 5) == 0) {
            int32_t displacement = *(int32_t *)( stret + 5 );
            dest = ( stret + 9 /* displacement is from the beginning of the next insn */ ) + displacement;
        } else if (memcmp(stret, prologue2, 4) == 0) {
            int8_t displacement = *(int8_t *)( stret + 4 );
            dest = ( stret + 5 /* displacement is from the beginning of the next insn */ ) + displacement;
        }
        
        if (dest) {
            if (callme == NULL) {
                /* ud2a instruction: illegal operation trap */
                static const unsigned char ud2a[2] = { 0x0F, 0x0B };
                return OBPatchCode(dest, 2, ud2a);
            } else {
                unsigned char jump_abs[13] = {
                    0x49, 0xBB, 0, 0, 0, 0, 0, 0, 0, 0,  /* mov $imm64, %r11 */
                    0x41, 0xFF, 0xE3                     /* jmp *%r11        */
                };
                *(uint64_t *)(jump_abs+2) = (uintptr_t)callme;  /* replace the imm64 with the called routine's entry point */
                return OBPatchCode(dest, 13, jump_abs);
            }
        } else {
            printf("objc_msgSend_stret (%p) does not start with expected instructions\n", stret);
        }
    }
#endif
    
#if defined(__i386__)
    const unsigned char *stret = dlsym(RTLD_DEFAULT, "objc_msgSend_stret");
    
    if (stret) {
        static const unsigned char prologue[11] = {
            0x8b, 0x44, 0x24, 0x08,   /* mov 0x8(%esp),%eax */
            0x8b,    0, 0x24,    0,   /* mov 0xc(%esp),%ecx */
            0x85, 0xc0,               /* test %eax, %eax */
            0x74,                     /* jump short if equal (8-bit displacement) */
        };
        // printf("OBPatchStretToNil: found objc_msgSend_stret at %p\n", stret);
        
        /* We actually don't care what the second instruction is, as long as it doesn't mess with the third */
        /* We'll accept any mov XX(XX),XX */
        if (memcmp(stret, prologue, 5) == 0 && (/* ModRM */ (stret[5] & 0xC7) == 0x44) && ( /* SIB */ stret[6] == 0x24 ) &&
            memcmp(stret+8, prologue+8, 3) == 0) {
            int8_t displacement = *(int8_t *)( stret + 11 );
            unsigned char *dest = (unsigned char *)( stret + 12 /* displacement is from the beginning of the next insn */ ) + displacement;
            // printf("OBPatchStretToNil: prologue looks good, dest is %p\n", dest);
            
            if (callme == NULL) {
                /* ud2a instruction: illegal operation trap */
                static const unsigned char ud2a[2] = { 0x0F, 0x0B };
                return OBPatchCode(dest, 2, ud2a);
            } else {
                unsigned char jump_rel[5] = {
                    0xE9, 0, 0, 0, 0,  /* jump near rel32 */
                };
                *(int32_t *)(jump_rel+1) = (ptrdiff_t)((unsigned char *)callme - (unsigned char *)(dest+5));  /* compute the rel32 jump offset */
                return OBPatchCode(dest, 5, jump_rel);
            }
        } else {
            printf("objc_msgSend_stret (%p) does not start with expected instructions\n", stret);
        }
    }
#endif
    
    return NO;
}

void OBLogStretToNil(void *hidden_structptr_arg, id rcvr_always_nil, SEL _cmd, ...)
{
    void *retaddr = __builtin_return_address(0);
    Dl_info info;
    
    if (dladdr(retaddr, &info)) {
        const char *objname;
        if (info.dli_fname) {
            objname = strrchr(info.dli_fname, '/');
            if (!objname || !objname[1])
                objname = info.dli_fname;
            else
                objname = objname + 1;
        } else {
            objname = "???";
        }
        NSLog(@"%s (%p, in %s) sent -%@ to nil, expecting struct return\n", info.dli_sname, retaddr, objname, NSStringFromSelector(_cmd));
    } else {
        NSLog(@"Function at %p sent -%@ to nil, expecting struct return\n", retaddr, NSStringFromSelector(_cmd));
    }
    
    /* For the common cases, let's poison the stack to make it obvious if the caller propagates the bad values somewhere */
    if (_cmd == @selector(frame) || _cmd == @selector(bounds)) {
#define CGNaNs __builtin_choose_expr(__builtin_types_compatible_p(CGFloat, float), __builtin_nansf("42"), __builtin_nans("42"))
        *((NSRect *)hidden_structptr_arg) = (NSRect){ {CGNaNs, CGNaNs}, {CGNaNs, CGNaNs} };
    }
}

#endif
