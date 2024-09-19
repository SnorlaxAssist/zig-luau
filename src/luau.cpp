#include "Luau/Common.h"

#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

static int assertionHandler(const char *expr, const char *file, int line, const char *function)
{
    printf("%s(%d): ASSERTION FAILED: %s\n", file, line, expr);
    return 1;
}

extern "C" void zig_registerAssertionHandler()
{
    Luau::assertHandler() = assertionHandler;
}

extern "C" void zig_luau_free(void *ptr)
{
    free(ptr);
}

extern "C" bool zig_luau_setflag_bool(const char *name, size_t nameLen, bool value)
{
    std::string flagName(name, nameLen);
    for (Luau::FValue<bool> *flag = Luau::FValue<bool>::list; flag; flag = flag->next)
        if (flagName == flag->name)
        {
            flag->value = value;
            return true;
        }
    return false;
}

extern "C" bool zig_luau_setflag_int(const char *name, size_t nameLen, int value)
{
    std::string flagName(name, nameLen);
    for (Luau::FValue<int> *flag = Luau::FValue<int>::list; flag; flag = flag->next)
        if (flagName == flag->name)
        {
            flag->value = value;
            return true;
        }
    return false;
}

extern "C" bool zig_luau_getflag_bool(const char *name, size_t nameLen, bool *value)
{
    std::string flagName(name, nameLen);
    for (Luau::FValue<bool> *flag = Luau::FValue<bool>::list; flag; flag = flag->next)
        if (flagName == flag->name)
        {
            *value = flag->value;
            return true;
        }
    return false;
}

extern "C" bool zig_luau_getflag_int(const char *name, size_t nameLen, int *value)
{
    std::string flagName(name, nameLen);
    for (Luau::FValue<int> *flag = Luau::FValue<int>::list; flag; flag = flag->next)
        if (flagName == flag->name)
        {
            *value = flag->value;
            return true;
        }
    return false;
}

extern "C" struct FlagGroup
{
    const char **names;
    int *types;
};

extern "C" FlagGroup zig_luau_getflags(const char *name, size_t nameLen, int value)
{
    std::vector<std::string> names_list;
    std::vector<int> types_list;

    for (Luau::FValue<bool> *flag = Luau::FValue<bool>::list; flag; flag = flag->next)
    {
        names_list.push_back(flag->name);
        types_list.push_back(0);
    }
    for (Luau::FValue<int> *flag = Luau::FValue<int>::list; flag; flag = flag->next)
    {
        names_list.push_back(flag->name);
        types_list.push_back(1);
    }

    size_t size = names_list.size();

    const char **names = new const char *[size + 1];
    int *types = new int[size];

    int i = 0;

    for (size_t i = 0; i < size; ++i)
    {
        names[i] = strdup(names_list[i].c_str());
        types[i] = types_list[i];
    }

    names[size + 1] = NULL;

    return {names, types};
}

extern "C" void zig_luau_freeflags(FlagGroup group)
{
    for (int i = 0; group.names[i] != NULL; i++)
    {
        free((void *)group.names[i]);
    }
    delete[] group.names;
    delete[] group.types;
}
