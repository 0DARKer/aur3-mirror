#include <argp.h>
#include <dirent.h>
#include <inttypes.h>
#include <limits.h>
#include <regex.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <alpm.h>

#define DBPATH "/var/lib/pacman/"
#define CACHEDIR "/var/cache/pacman/pkg/"

const char *argp_program_version = "pkgcacheclean "VERSION;
const char *argp_program_bug_address = "auguste@gmail.com";

static char doc[] =
    "pkgcacheclean -- a simple utility to clean pacman cache.\v"
    "For installed packages, preserve_number of versions are reserved. This\n"
    "includes the current version and the newest (preserve_number - 1) of\n"
    "the remaining. For uninstalled packages all versions are deleted.\n"
    "The default number is 2.";
static char args_doc[] = "[preserve_number]";

static struct argp_option options[] =
{
    { .doc = "" },
    { .name = "dry-run", .key = 'n', .doc = "Perform a trial run with no changes made" },
    { .name = "verbose", .key = 'v', .doc = "Verbose output" },
    { .name = "quiet", .key = 'q', .doc = "Suppress output, default" },
    { .doc = NULL }
};

static regex_t pkgnamesplit;
static regex_t pkgnametest;

struct pkginfo
{
    char *name;
    char *version;
    char *filename;
};

struct arguments
{
    int dry_run;
    int preserve;
    int verbose;
};

static char *dupsubstr(const char *str, const int start, const int end)
{
    char *ret;
    const int len = end - start;

    ret = malloc(sizeof(char) * (len + 1));
    strncpy(ret, str + start, len);
    ret[len] = '\0';

    return ret;
}

static struct pkginfo * get_pkginfo_from_filename(const char * const filename)
{
    struct pkginfo *ret;
    static regmatch_t match[3];

    ret = malloc(sizeof(struct pkginfo));
    regexec(&pkgnamesplit, filename, 3, match, 0);
    ret->name = dupsubstr(filename, match[1].rm_so, match[1].rm_eo);
    ret->version = dupsubstr(filename, match[2].rm_so, match[2].rm_eo);
    ret->filename = strdup(filename);

    return ret;
}

static struct pkginfo * get_pkginfo_from_pmpkg(pmpkg_t *pmpkg)
{
    struct pkginfo *ret;

    ret = malloc(sizeof(struct pkginfo));
    ret->name = strdup(alpm_pkg_get_name(pmpkg));
    ret->version = strdup(alpm_pkg_get_version(pmpkg));
    ret->filename = NULL;

    return ret;
}

static void free_pkginfo(struct pkginfo * pkg)
{
    free(pkg->name);
    free(pkg->version);
    free(pkg->filename);
    free(pkg);
}

static int pkgcomp(const void *a, const void *b)
{
    struct pkginfo *ap = *(struct pkginfo **)a;
    struct pkginfo *bp = *(struct pkginfo **)b;

    int namecomp = strcmp(ap->name, bp->name);

    return namecomp ? namecomp : -alpm_pkg_vercmp(ap->version,
            bp->version);
}

static int pkgnamecomp(const void *a, const void *b)
{
    return strcmp((*(struct pkginfo **)a)->name,
            (*(struct pkginfo **)b)->name);
}

static int ispackage(const struct dirent *file)
{
    return regexec(&pkgnametest, file->d_name, 0, NULL, 0) == 0;
}

static void free_pkginfo_array(struct pkginfo **pkgs, const int n)
{
    int i;

    for (i = 0; i < n; i++)
        free_pkginfo(pkgs[i]);
    free(pkgs);
}

static off_t get_file_size(const char *filename)
{
    struct stat st;

    stat(filename, &st);
    return st.st_size;
}

static error_t parse_opt(int key, char *arg, struct argp_state *state)
{
    struct arguments *argument = state -> input;

    switch (key)
    {
        case 'n':
            argument->dry_run = 1;
            break;
        case 'v':
            argument->verbose = 1;
            break;
        case 'q':
            argument->verbose = 0;
            break;
        case ARGP_KEY_ARG:
            if (argument->preserve)
                return ARGP_ERR_UNKNOWN;
            argument->preserve = atoi(arg);
            if (argument->preserve <= 0)
                return ARGP_ERR_UNKNOWN;
            break;
        default:
            return ARGP_ERR_UNKNOWN;
    }

    return 0;
}

int main(const int argc, char ** __restrict__ argv)
{
    int i, n, m, len, count = 0;
    off_t total_size = 0;
    pmdb_t *db;
    alpm_list_t *pkglist;
    struct dirent **dir;
    struct pkginfo **cachepkg, **localpkg;
    struct pkginfo **hit = NULL;
    const char *current = "", *name;
    char cachedir[PATH_MAX] = CACHEDIR;
    struct argp arg_parser = { .options = options, .parser = parse_opt,
        .args_doc = args_doc, .doc = doc };
    struct arguments args = { .dry_run = 0, .preserve = 0, .verbose = 0 };

    argp_parse(&arg_parser, argc, argv, 0, NULL, &args);
    if (!args.preserve)
        args.preserve = 2;

    if (!args.dry_run && getuid())
    {
        puts("please run as root.");
        exit(EXIT_FAILURE);
    }

    len = strlen(cachedir);
    regcomp(&pkgnamesplit, "^(.*)-([^-]*-[^-]*)-[^-]*$", REG_EXTENDED);
    regcomp(&pkgnametest, "^.*-("CARCH"|any).[^-]*$", REG_EXTENDED);

    alpm_initialize();

    n = scandir(cachedir, &dir, ispackage, NULL);
    cachepkg = malloc(sizeof(struct pkginfo *) * n);
    for (i = 0; i < n; free(dir[i]), i++)
        cachepkg[i] = get_pkginfo_from_filename(dir[i]->d_name);
    free(dir);
    qsort(cachepkg, n, sizeof(struct pkginfo *), pkgcomp);

    alpm_option_set_dbpath(DBPATH);
    db = alpm_option_get_localdb();
    pkglist = alpm_db_get_pkgcache(db);
    m = alpm_list_count(pkglist);
    localpkg = malloc(sizeof(struct pkginfo *) * m);
    for (i = 0; i < m; i++, pkglist = alpm_list_next(pkglist))
        localpkg[i] = get_pkginfo_from_pmpkg(alpm_list_getdata(pkglist));
    qsort(localpkg, m, sizeof(struct pkginfo *), pkgnamecomp);
    alpm_list_free_inner(pkglist, (alpm_list_fn_free)alpm_pkg_free);
    alpm_list_free(pkglist);

    for (i = 0; i < n; i++)
    {
        name = cachepkg[i]->name;
        if (strcmp(name, current))
        {
            current = name;
            hit = bsearch(cachepkg + i, localpkg, m,
                    sizeof(struct pkginfo *), pkgnamecomp);
            count = hit ? 0 : args.preserve;
        }
        if (!hit || alpm_pkg_vercmp((*hit)->version,
                    cachepkg[i]->version))
        {
            count++;
            if (count >= args.preserve)
            {
                strcpy(cachedir + len, cachepkg[i]->filename);
                if (args.verbose)
                {
                    printf("remove: %s\n", cachepkg[i]->filename);
                    total_size += get_file_size(cachedir);
                }
                if (!args.dry_run)
                    unlink(cachedir);
            }
        }
    }

    if (args.verbose)
        printf("\ntotal: %"PRIuMAX" bytes\n", (uintmax_t)total_size);

    free_pkginfo_array(cachepkg, n);
    free_pkginfo_array(localpkg, m);

    alpm_release();
    regfree(&pkgnametest);
    regfree(&pkgnamesplit);

    return EXIT_SUCCESS;
}
