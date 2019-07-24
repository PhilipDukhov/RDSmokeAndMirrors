#import "RDBlockObject.h"
#import "RDType.h"
#import "RDPrivate.h"
#import <objc/runtime.h>
#import <ffi/ffi.h>

static const char *kBlockCaptureAssocKey = "RDBlockCaptureAssocKey";

struct RDBlockObjectCapture {
    RDBlockDescriptor descriptor;
    ffi_cif cifExt;
    ffi_cif cifInt;
    SEL selector;
    void *fptr;
};

void RDBlockObjectTramp(ffi_cif *cif, void *ret, void* args[], void *cap) {
    __unsafe_unretained id self = (__bridge id)args[0];
    RDBlockObjectCapture *capture = (RDBlockObjectCapture *)cap;
    SEL selector = capture->selector;
    
    Method method = class_getInstanceMethod(object_getClass(self), selector);
    if (method == NULL)
        return;

    unsigned extArgCount = capture->cifExt.nargs;
    void *argValues[extArgCount];

    argValues[0] = &self;
    argValues[1] = &selector;
    for (unsigned i = 2; i < extArgCount; ++i)
        argValues[i] = args[i - 1];
    
    ffi_call(&capture->cifExt, method_getImplementation(method), ret, argValues);
    
    return;
}


@interface RDType(RDInvocation)

- (ffi_type *_Nullable)_inv_ffi_type;
+ (void)_inv_ffi_type_destroy:(ffi_type *)type;

@end

@implementation RDBlockObject {
    RDBlockInfoFlags _flags;
    int _reserved;
    void (*_invoke)(id, ...);
    RDBlockDescriptor *_descriptor;
}

+ (void)initialize {
    if (self == RDBlockObject.self)
        return;
    
    RDBlockObjectCapture *capture = (RDBlockObjectCapture *)calloc(1, sizeof(RDBlockObjectCapture));
        
    SEL selector = [self selectorForCalling];
    if (selector == NULL)
        return;
    
    capture->selector = selector;
        
    Method method = class_getInstanceMethod(self, selector);
    if (method == NULL)
        return;

    RDMethodSignature *sig = [RDMethodSignature signatureWithObjcTypeEncoding:method_getTypeEncoding(method)];
    if (sig == nil)
        return;

    NSUInteger extArgCount = sig.arguments.count;    
    {
        ffi_type **argTypes = (ffi_type **)calloc(extArgCount, sizeof(ffi_type *));

        for (NSUInteger i = 0; i < extArgCount; ++i)
            if (ffi_type *type = sig.arguments[i].type._inv_ffi_type; type != NULL)
                argTypes[i] = type;
            else
                return;

        ffi_type *retType = sig.returnValue.type._inv_ffi_type;
        if (retType == NULL)
            return;
        
        if (ffi_prep_cif(&capture->cifExt, FFI_DEFAULT_ABI, (unsigned)extArgCount, retType, argTypes) != FFI_OK)
            return;
    }
    
    NSUInteger intArgCount = extArgCount - 1;
    {
        ffi_type **argTypes = (ffi_type **)calloc(intArgCount, sizeof(ffi_type *));
        for (NSUInteger i = 0; i < intArgCount; ++i)
            argTypes[i] = capture->cifExt.arg_types[i + i];
        
        ffi_type *retType = capture->cifExt.rtype;
        if (ffi_prep_cif(&capture->cifInt, FFI_DEFAULT_ABI, (unsigned)intArgCount, retType, argTypes) != FFI_OK)
            return;
    }
    
    ffi_closure *closure = (ffi_closure *)ffi_closure_alloc(sizeof(ffi_closure), &capture->fptr);
    if (closure == NULL)
        return;
        
    if (ffi_prep_closure_loc(closure, &capture->cifInt, RDBlockObjectTramp, capture , capture->fptr) != FFI_OK)
        return;

    capture->descriptor = (RDBlockDescriptor) {
        .reserved=0,
        .size=class_getInstanceSize(self),
        .copyHelper = NULL,
        .disposeHelper = NULL,
        .signature = NULL, // TODO: fill in
    };
    
    objc_setAssociatedObject(self, kBlockCaptureAssocKey, (__bridge id)capture, OBJC_ASSOCIATION_ASSIGN);
}

+ (SEL)selectorForCalling {
    return @selector(invoke);
}

- (instancetype)init {
    self = [super init];
    if (self) {
        if (class_getInstanceSize(class_getSuperclass(RDBlockObject.self)) != sizeof(id)
            || (uintptr_t)&_flags - (uintptr_t)self != offsetof(RDBlockInfo, flags)
            || (uintptr_t)&_reserved - (uintptr_t)self != offsetof(RDBlockInfo, reserved)
            || (uintptr_t)&_invoke - (uintptr_t)self != offsetof(RDBlockInfo, invoke)
            || (uintptr_t)&_descriptor - (uintptr_t)self != offsetof(RDBlockInfo, descriptor))
            return nil; // layout compromized

        RDBlockObjectCapture *capture = (__bridge RDBlockObjectCapture *)objc_getAssociatedObject(self.class, kBlockCaptureAssocKey);

        _flags = (RDBlockInfoFlags)0;
        _invoke = (void (*)(id, ...))capture->fptr;
        _descriptor = &capture->descriptor;
    }
    return self;
}

- (instancetype)initWithCFunctionPointer:(void (*)(id, ...))fptr {
    self = [self init];
    if (self) {
        _invoke = fptr;
    }
    return self;
}

- (void)invoke {
    // do nothing
}

- (void (^)(void))asBlock {
    return (__bridge void (^)(void))(__bridge void *)self;
}

@end
