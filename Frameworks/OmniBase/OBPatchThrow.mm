// Copyright 2015-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
//  OBPatchThrow.mm
//  $Id$
//

extern "C" {

#import <OmniBase/OBPatchTrap.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/OBBacktraceBuffer.h>
    
};

#include <cxxabi.h>
#include <typeinfo>

#if defined(__x86_64__)

extern "C" {
    static void OBAboutToThrow(void * thrown_exception, void * tinfo, void (*dest)(void *)) __attribute__((used, visibility("hidden")));
    void pre_throw_trampoline_1(void) __attribute__((naked, noreturn, visibility("hidden")));
    void pre_throw_trampoline_2(void) __attribute__((naked, noreturn, visibility("hidden")));
    
    // For now we'll enable this only via OmniCrashCatcher instead of having it be a constructor. This means that we'll not get backtrace buffers for anything that happens early on, but those wouldn't get reported to us anyway unless OCC had been enabled.
    // BOOL OBPatchCxxThrow(void) __attribute__((constructor));
};

static void OBAboutToThrow(void * thrown_exception, void * tinfo, void (*dest)(void *))
{
    /* Our arguments are what is about to be passed to __cxa_throw(). See http://mentorembedded.github.io/cxx-abi/abi-eh.html for a description of what they are:
         thrown_exception: a pointer to the object being thrown
         tinfo: C++ type info about that object
         dest: a destructor for that object
     
     In the case of an ObjC exception, for example, the "object being thrown" is an (NSException *), so thrown_exception is an (NSException **).
     The thrown_exception pointer points after a buffer large enough to hold a struct __cxa_exception, but that struct isn't filled in yet--- it gets filled in by __cxa_throw().
    */
    std::type_info *t = (std::type_info *)tinfo;
    ::OBRecordBacktrace(t->name(), OBBacktraceBuffer_CxxException);
}

/* We clobber the first few bytes of the patched function with our jump. The trampoline needs to do whatever those instructions did before returning. For simplicity, we do them right at the front of the trampoline, and simply compare our bytes against the clobbered bytes to see if it's safe to insert our patch. */
#define PROLOGUE_LENGTH_1  12
asm(
    "_pre_throw_trampoline_1:"
    "    pushq %rbp\n"
    "    movq  %rsp, %rbp\n"
    "    pushq %r15\n"
    "    pushq %r14\n"
    "    pushq %r13\n"
    "    pushq %r12\n"
    /* end of common prologue */
    
    /* save callee-clobbered registers (args) and call our function */
    "    pushq %rcx\n"   /* Not strictly necesary to save this, but we need to keep the stack aligned */
    "    pushq %rdx\n"
    "    pushq %rdi\n"
    "    pushq %rsi\n"
    "    callq _OBAboutToThrow\n"
    "    popq  %rsi\n"
    "    popq  %rdi\n"
    "    popq  %rdx\n"
    "    popq  %rcx\n"
    
    /* jump to the point in cxa_throw after the common prologue */
    "    movq  ___cxa_throw@GOTPCREL(%rip), %rax\n"
    "    addq  $12, %rax\n"   /* must be equal to PROLOGUE_LENGTH_1 */
    "    jmp *%rax\n");

#define PROLOGUE_LENGTH_2  14
asm(
    "_pre_throw_trampoline_2:"
    "    pushq %rbp\n"
    "    movq  %rsp, %rbp\n"
    "    pushq %r15\n"
    "    pushq %r14\n"
    "    pushq %r12\n"
    "    pushq %rbx\n"
    "    movq %rdx, %r14\n"
    /* end of common prologue */
    
    /* save callee-clobbered registers (args) and call our function */
    "    pushq %rcx\n"   /* Not strictly necesary to save this, but we need to keep the stack aligned */
    "    pushq %rdx\n"
    "    pushq %rdi\n"
    "    pushq %rsi\n"
    "    callq _OBAboutToThrow\n"
    "    popq  %rsi\n"
    "    popq  %rdi\n"
    "    popq  %rdx\n"
    "    popq  %rcx\n"
    
    /* jump to the point in cxa_throw after the common prologue */
    "    movq  ___cxa_throw@GOTPCREL(%rip), %rax\n"
    "    addq  $14, %rax\n"   /* must be equal to PROLOGUE_LENGTH_2 */
    "    jmp *%rax\n");



BOOL OBPatchCxxThrow(void)
{
    void *cxa_throw = (void *)&__cxxabiv1::__cxa_throw;
    if (!cxa_throw)
        return NO;
    
    void (*trampoline)();
    
    
    if (::memcmp(cxa_throw, (void *)pre_throw_trampoline_1, PROLOGUE_LENGTH_1) == 0) {
        trampoline = pre_throw_trampoline_1;
    } else if (::memcmp(cxa_throw, (void *)pre_throw_trampoline_2, PROLOGUE_LENGTH_2) == 0) {
        trampoline = pre_throw_trampoline_2;
    } else {
#ifdef DEBUG
        NSLog(@"Unable to patch __cxa_throw: prologue mismatch (prologue has beginning %@)", [NSData dataWithBytes:cxa_throw length:16]);
#endif
        return NO;
    }
    
    unsigned char jump_abs[] = {
        0x48, 0xB8, 0, 0, 0, 0, 0, 0, 0, 0,  /* mov $imm64, %rax */
        0xFF, 0xE0                           /* jmp *%rax        */
    };
    _Static_assert(sizeof(jump_abs) <= PROLOGUE_LENGTH_1, "PROLOGUE_LENGTH is smaller than patch sequence");
    _Static_assert(sizeof(jump_abs) <= PROLOGUE_LENGTH_2, "PROLOGUE_LENGTH is smaller than patch sequence");
    
    *(uint64_t *)(jump_abs+2) = (uintptr_t)trampoline;
    BOOL ok = OBPatchCode(cxa_throw, sizeof(jump_abs), jump_abs);
    
#ifdef DEBUG
    if (!ok) {
        NSLog(@"Unable to patch __cxa_throw: OBPatchCode returned NO");
    }
#endif
    
    return ok;
}

#endif


