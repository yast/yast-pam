#
# Makefile.am for y2a_pam/src
#

AM_CXXFLAGS = -Wall # -g # -pedantic # -W

plugin_LTLIBRARIES = libpy2ag_pam.la
noinst_LTLIBRARIES = liby2ag_pam.la

liby2ag_pam_la_SOURCES =                    \
	PamAgent.cc		\
	PamAgent.h
liby2ag_pam_la_LDFLAGS = -version-info 2:0

libpy2ag_pam_la_SOURCES =                           \
        $(liby2ag_pam_la_SOURCES)                   \
        Y2CCPamAgent.cc
libpy2ag_pam_la_LDFLAGS = -version-info 2:0

INCLUDES = -I$(includedir)

