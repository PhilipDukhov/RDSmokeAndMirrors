#import <Foundation/Foundation.h>
#include <algorithm>

NS_ASSUME_NONNULL_BEGIN

extern "C" id _Nullable objc_autorelease(id _Nullable value);
extern "C" void objc_autoreleasePoolPop(void *pool);
extern "C" void *objc_autoreleasePoolPush(void);
extern "C" id _Nullable objc_autoreleaseReturnValue(id _Nullable value);
extern "C" void objc_copyWeak(id _Nullable *_Nonnull dest, id _Nullable *_Nonnull src);
extern "C" void objc_destroyWeak(id _Nullable *_Nonnull object);
extern "C" id objc_initWeak(id _Nullable *_Nonnull object, id _Nullable value);
extern "C" id _Nullable objc_loadWeak(id _Nullable *_Nonnull object);
extern "C" id _Nullable objc_loadWeakRetained(id _Nullable *_Nonnull object);
extern "C" void objc_moveWeak(id _Nullable *_Nonnull dest, id _Nullable *_Nonnull src);
extern "C" void objc_release(id _Nullable value);
extern "C" id _Nullable objc_retain(id _Nullable value);
extern "C" id _Nullable objc_retainAutorelease(id _Nullable value);
extern "C" id _Nullable objc_retainAutoreleaseReturnValue(id _Nullable value);
extern "C" id _Nullable objc_retainAutoreleasedReturnValue(id _Nullable value);
extern "C" id _Nullable objc_retainBlock(id _Nullable value);
extern "C" void objc_storeStrong(id _Nullable *_Nonnull object, id _Nullable value);
extern "C" id objc_storeWeak(id _Nullable *_Nonnull object, id _Nullable value);

static inline long rd_retainCount(id _Nullable value) {
    return value ? 0 : CFGetRetainCount((__bridge CFTypeRef)value);
}

template<typename T, typename U>
NSArray<U *> *_Nullable map_nn(NSArray<T *> *_Nullable source, U *_Nullable (^_Nonnull block)(T *_Nonnull)) {
    if (source == nil)
        return nil;
    
    NSMutableArray<U *> *result = [NSMutableArray arrayWithCapacity:source.count];
    for (T *obj in source)
        if (U *res = block(obj); res)
            [result addObject:res];
    
    return result;
}

template<typename R, typename ... T>
NSArray<R *> *_Nonnull zip(R *_Nullable (^_Nonnull zipper)(T *_Nonnull...), NSArray<T *> *_Nullable... args) {
    NSMutableArray<R *> *result = [NSMutableArray array];
    for (NSUInteger i = 0; i < std::min(args.count...); ++i)
        if (R *object = zipper(args[i]...); object)
            [result addObject:object];
    
    return result;
}

NS_ASSUME_NONNULL_END