/*
 * YaST2: Core system
 *
 * Description:
 *   YaST2 SCR: Pam agent implementation
 *
 * Authors:
 *   Thorsten Kukuk <kukuk@suse.de>
 *
 * $Id$
 */

#define _GNU_SOURCE

#include <string.h>
#include <stdio.h>
#include <ctype.h>
#include <unistd.h>
#include <sys/stat.h>

#include "PamAgent.h"

/**
 * Constructor
 */
PamAgent::PamAgent() : SCRAgent()
{
}

/**
 * Destructor
 */
PamAgent::~PamAgent()
{
}

/**
 * Dir
 */
YCPValue PamAgent::Dir(const YCPPath& path)
{
    y2error("Wrong path '%s' in Read().", path->toString().c_str());
    return YCPVoid();
}

struct pam_config {
  char *type;
  char *control;
  char *module;
  char *arguments;
  char *comments;
};


static void
free_pam_config (struct pam_config *data)
{
  if (data->type)
    {
      free (data->type);
      data->type = NULL;
    }
  if (data->control)
    {
      free (data->control);
      data->control = NULL;
    }
  if (data->module)
    {
      free (data->module);
      data->module = NULL;
    }
  if (data->arguments)
    {
      free (data->arguments);
      data->arguments = NULL;
    }
  if (data->comments)
    {
      free (data->comments);
      data->comments = NULL;
    }
}

/* read_pam_config:
 * expects a file handle for a PAM config file and a pointer
 * to allocated memory for the pam_config data.
 * returns 0 if there is no more line, 1 if there is still more
 * data and a negative value for an error.
 */
static int
read_pam_config (FILE *fp, struct pam_config *data)
{
  char *line = NULL, *cp, *entry;
  size_t len = 0;

 next_line:
  if (feof(fp))
    return 0;

  ssize_t n = getline (&line, &len, fp);
  if (n < 0)
    return -1;
  if (line[n - 1] == '\n')
    line[n - 1] = '\0';

  /* If the line is blank it is ignored.  */
  if (line[0] == '\0')
    goto next_line;

  /* Search for a comment at first */
  cp = strchr (line, '#');
  if (cp != NULL)
    {
      *cp++ = '\0';
#if 0
      while (isspace (*cp) && *cp != '\0')
	++cp;
#endif
      data->comments = strdup (cp);
    }

  if (line[0] == '\0')
    return 1;

  /* search type */
  entry = line;
  while (isspace (*entry) && *entry != '\0')
    ++entry;
  cp = entry;
  while (!isspace (*cp) && *cp != '\0')
    ++cp;
  *cp = '\0';
  if (strlen (entry) == 0)
    return 1;

  data->type = strdup (entry);
  entry = cp; ++entry;

  /* search control */
  while (isspace (*entry) && *entry != '\0')
    ++entry;
  cp = entry;
  while (!isspace (*cp) && *cp != '\0')
    ++cp;
  *cp = '\0';
  if (strlen (entry) == 0)
    {
      free_pam_config(data);
      free (line);
      return -1;
    }
  data->control = strdup (entry);
  entry = cp; ++entry;

  /* search module */
  while (isspace (*entry) && *entry != '\0')
    ++entry;
  cp = entry;
  while (!isspace (*cp) && *cp != '\0')
    ++cp;
  *cp = '\0';
  if (strlen (entry) == 0)
    {
      free_pam_config(data);
      free (line);
      return -1;
    }
  data->module = strdup (entry);
  entry = cp; ++entry;

  /* search arguments */
  while (isspace (*entry) && *entry != '\0')
    ++entry;
#if 0
  cp = entry;
  while (!isspace (*cp) && *cp != '\0')
    ++cp;
  *cp = '\0';
#endif
  if (entry && strlen (entry) != 0)
    data->arguments = strdup (entry);

  /* Free the buffer.  */
  free (line);
  return 1;
}

/* read_unix2_config:
 * expects a file handle for the pam_unix2 config file and a pointer
 * to allocated memory for the pam_config data.
 * returns 0 if there is no more line, 1 if there is still more
 * data and a negative value for an error.
 * This function can also read pam_pwcheck.conf.
 */
static int
read_unix2_config (FILE *fp, struct pam_config *data)
{
  char *line = NULL, *cp, *entry;
  size_t len = 0;

 next_line:
  if (feof(fp))
    return 0;

  ssize_t n = getline (&line, &len, fp);
  if (n < 0)
    return -1;
  if (line[n - 1] == '\n')
    line[n - 1] = '\0';

  /* If the line is blank it is ignored.  */
  if (line[0] == '\0')
    goto next_line;

  /* Search for a comment at first */
  cp = strchr (line, '#');
  if (cp != NULL)
    {
      *cp++ = '\0';
#if 0
      while (isspace (*cp) && *cp != '\0')
	++cp;
#endif
      data->comments = strdup (cp);
    }

  if (line[0] == '\0')
    return 1;

  /* search type (format is "type:") */
  entry = line;
  while (isspace (*entry) && *entry != '\0')
    ++entry;
  cp = entry;
  while (!isspace (*cp) && *cp != '\0' && *cp != ':')
    ++cp;
  *cp = '\0';
  if (strlen (entry) == 0)
    return 1;

  data->type = strdup (entry);
  entry = cp; ++entry;

  /* search arguments */
  while ((isspace (*entry) || *cp == ':') && *entry != '\0')
    ++entry;
  if (entry && strlen (entry) != 0)
    data->arguments = strdup (entry);

  /* Free the buffer.  */
  free (line);
  return 1;
}

/**
 * Read
 *
 * path is <service>[.<type>.<module>]
 *
 * service is a PAM config file in /etc/pam.d
 * type is one of auth, session, password or acct
 * module is the name of a PAM module
 *
 */
YCPValue PamAgent::Read(const YCPPath &path, const YCPValue& arg = YCPNull())
{
  y2debug ("PamAgent::Read(%s)", path->toString().c_str());

  if (path->length() == 1)
    {
      /* Read whole file */
      YCPList config_list;
      string conf_name = string("/etc/pam.d/") + path->component_str(0);
      struct pam_config data;

      memset (&data, 0, sizeof (data));
      FILE *fp = fopen (conf_name.c_str(), "r");
      if (fp == NULL)
        {
	  y2warning ("unknown config file in path '%s'", path->toString().c_str());
	  return YCPVoid();
        }

      while (read_pam_config (fp, &data) > 0)
	{
	  YCPMap entries;
	  if (data.type)
	    entries->add (YCPString ("type"), YCPString (data.type));
	  if (data.control)
	    entries->add (YCPString ("control"), YCPString (data.control));
	  if (data.module)
	    entries->add (YCPString ("module"), YCPString (data.module));
	  if (data.arguments)
	    entries->add (YCPString ("arguments"), YCPString (data.arguments));
	  if (data.comments)
	    entries->add (YCPString ("comments"), YCPString (data.comments));
	  config_list->add (entries);
	  free_pam_config (&data);
	}

      fclose (fp);
      return config_list;
    }
  else if (path->length() == 3)
    {
      /* Read only special lines */
      YCPList config_list;
      if (strcmp (path->component_str(0).c_str(), "all") == 0 &&
	  (strncmp (path->component_str(2).c_str(), "pam_unix", 8) == 0 ||
	   strcmp (path->component_str(2).c_str(), "pam_pwcheck") == 0))
	{
	  struct pam_config data;
	  string conf_name;

	  if (strcmp (path->component_str(2).c_str(), "pam_pwcheck") == 0)
	    conf_name = string("/etc/security/pam_pwcheck.conf");
	  else
	    conf_name = string("/etc/security/pam_unix2.conf");

	  memset (&data, 0, sizeof (data));
	  FILE *fp = fopen (conf_name.c_str(), "r");
	  if (fp == NULL)
	    {
	      y2warning ("file not found: '%s'", conf_name.c_str());
	      return YCPVoid();
	    }

	  while (read_unix2_config (fp, &data) > 0)
	    {
	      // data.type should not be NULL
	      if (data.type == NULL)
		{
		  free_pam_config(&data);
		  continue;
		}

	      if (strcmp (data.type, path->component_str(1).c_str()) == 0)
		{
		  YCPMap entries;

		  if (data.type)
		    entries->add (YCPString ("type"), YCPString (data.type));
		  if (data.control)
		    entries->add (YCPString ("control"), YCPString (data.control));
		  if (data.module)
		    entries->add (YCPString ("module"), YCPString (data.module));
		  if (data.arguments)
		    entries->add (YCPString ("arguments"),
				  YCPString (data.arguments));
		  if (data.comments)
		    entries->add (YCPString ("comments"),
				  YCPString (data.comments));
		  config_list->add (entries);
		}
	      free_pam_config (&data);
	    }
	  fclose (fp);
	  return config_list;
	}
      else
	{
	  string conf_name = string("/etc/pam.d/") + path->component_str(0);
	  struct pam_config data;

	  memset (&data, 0, sizeof (data));
	  FILE *fp = fopen (conf_name.c_str(), "r");
	  if (fp == NULL)
	    {
	      y2warning ("unknown config file in path '%s'", path->toString().c_str());
	      return YCPVoid();
	    }

	  while (read_pam_config (fp, &data) > 0)
	    {
	      // If one of both is NULL, this cannot be our
	      // entry.
	      if (data.type == NULL || data.module == NULL)
		{
		  free_pam_config(&data);
		  continue;
		}

	      // data.module can be a complete path to the module,
	      // but our interface only allows the name without path
	      // end ending .so suffix.
	      char *cp = strrchr (data.module, '/');
	      if (cp == NULL)
		cp = data.module;
	      else
		cp++;
	      cp = strdup (cp);
	      // Remove the ending ".so"
	      cp[strlen(cp) - 3] = '\0';

	      if (strcmp (data.type, path->component_str(1).c_str()) == 0 &&
		  strcmp (cp, path->component_str(2).c_str()) == 0)
		{
		  YCPMap entries;

		  if (data.type)
		    entries->add (YCPString ("type"), YCPString (data.type));
		  if (data.control)
		    entries->add (YCPString ("control"), YCPString (data.control));
		  if (data.module)
		    entries->add (YCPString ("module"), YCPString (data.module));
		  if (data.arguments)
		    entries->add (YCPString ("arguments"),
				  YCPString (data.arguments));
		  if (data.comments)
		    entries->add (YCPString ("comments"),
				  YCPString (data.comments));
		  config_list->add (entries);
		}
	      free (cp);
	      free_pam_config (&data);
	    }
	  fclose (fp);
	  return config_list;
	}
    }

  y2error ("unknown command in path '%s'", path->toString().c_str());
  return YCPVoid();
}

/* identify a substring in another string, where the substring
   is complete: means we have a blank before and after. */
static char *
identify_substring (const char *str, const char *search)
{
  char *cp = strstr (str, search);

  if (cp == NULL) /* str does not contain search */
    return NULL;

  if (cp == str) /* search is the beginning of str */
    {
      if ((str[strlen(search)] == '\0') || isspace(str[strlen(search)]))
	return cp;
      else
	return NULL; /* only the beginning of the string is identical */
    }

  if (isspace(cp[-1]) &&
      ((cp[strlen(search)] == '\0') || isspace(cp[strlen(search)])))
    return cp;

  return NULL;
}

static char *
add_string (const char *str, const char *add)
{
  if (str == NULL)
    return strdup (add);

  if (identify_substring (str, add) == NULL)
    {
      char *ptr, *cp = (char *)malloc (strlen (str) + strlen (add) + 2);

      ptr = stpcpy (cp, add);
      ptr = stpcpy (ptr, " ");
      ptr = stpcpy (ptr, str);
      return cp;
    }
  else
    return strdup (str);

  return NULL;
}

static char *
remove_string (const char *str, const char *rem)
{
  /* if we don't have something, we don't need to remove something */
  if (str == NULL)
    return NULL;

  /* if it is the same, return empty string */
  if (strcmp (str, rem) == 0)
    return strdup ("");

  char *t = strdup (str);
  char *cp = identify_substring (t, rem);

  if (cp == NULL) /* we don't have this substring */
    {
      y2debug ("%s not found in %s", rem, t);
      free (t);
      return NULL;
    }

  char *cp1 = cp + strlen(rem);
  if (isspace(cp1[0]))
    ++cp1;
  strcpy (cp, cp1);

  return t;
}

/**
 * Write
 */
YCPValue PamAgent::Write(const YCPPath &path, const YCPValue& value, const YCPValue& arg = YCPNull())
{
  int add;
  char *param;

  /* FIXME: strdup for param will create a memory leak */

  y2debug ("PamAgent::Write(%s,%s)", path->toString().c_str(),
	   value->toString().c_str());

  param = strdup (value->toString().c_str());
  if (param[0] == '"')
    {
      ++param;
      param[strlen(param) - 1] = '\0';
    }

  if (param[0] == '-')
    add = 0;
  else if (param[0] == '+')
    add = 1;
  else
    {
      y2debug ("PamAgent::Write: don't know what todo with %s", param);
      return YCPVoid();
    }
  ++param;

  if (path->length() == 3)
    {
      /* Modify special lines.  */
      bool ret = false;
      if (strcmp (path->component_str(0).c_str(), "all") == 0 &&
	  (strncmp (path->component_str(2).c_str(), "pam_unix", 8) == 0 ||
	   strcmp (path->component_str(2).c_str(), "pam_pwcheck") == 0))
	{
	  string conf_name;
	  struct pam_config data;
	  char config_tmp[] = "/etc/security/.YaST2.pam.agent.XXXXXX";
	  int fd;
	  struct stat sbuf;
	  FILE *fout;

	  if (strcmp (path->component_str(2).c_str(), "pam_pwcheck") == 0)
	    conf_name = string("/etc/security/pam_pwcheck.conf");
	  else
	    conf_name = string("/etc/security/pam_unix2.conf");

	  FILE *fp = fopen (conf_name.c_str(), "r");
	  if (fp == NULL)
	    {
	      y2warning ("file not found: '%s'", conf_name.c_str());
	      return YCPVoid();
	    }

	  fd = mkstemp (config_tmp);
	  if (fd < 0)
	    {
	      y2error ("PamAgent::Write: cannot create tmp file");
	      return YCPVoid();
	    }
	  fout = fdopen (fd, "w");

	  memset (&data, 0, sizeof (data));

	  while (read_unix2_config (fp, &data) > 0)
	    {
	      char *new_arg = NULL;

	      if (data.type == NULL)
		{
		  if (data.comments != NULL)
		    fprintf (fout, "#%s\n", data.comments);
		  free_pam_config (&data);
		  continue;
		}

	      if (strcmp (data.type, path->component_str(1).c_str()) == 0)
		{
		  YCPMap entries;

		  if (data.type)
		    entries->add (YCPString ("type"), YCPString (data.type));
		  if (data.control)
		    entries->add (YCPString ("control"), YCPString (data.control));
		  if (data.module)
		    entries->add (YCPString ("module"), YCPString (data.module));
		  {
		    /* Modify arguments */

		    if (add)
		      new_arg = add_string (data.arguments, param);
		    else
		      new_arg = remove_string (data.arguments, param);

		    if (new_arg)
		      {
			entries->add (YCPString ("arguments"),
				      YCPString (new_arg));
			// free (new_arg);
		      }
		    ret = true;
		  }
		  if (data.comments)
		    entries->add (YCPString ("comments"),
				  YCPString (data.comments));
		}

	      fprintf (fout, "%s:", data.type);
	      if (new_arg)
		fprintf (fout, "\t%s", new_arg);
	      else if (data.arguments)
		fprintf (fout, "\t%s", data.arguments);
	      if (data.comments)
		fprintf (fout, " #%s", data.comments);
	      fprintf (fout, "\n");

	      if (new_arg)
		free (new_arg);
	      free_pam_config (&data);
	    }
	  fclose (fout);
	  fclose (fp);
	  if (stat (conf_name.c_str(), &sbuf) == 0)
	    {
	      chown (config_tmp, sbuf.st_uid, sbuf.st_gid);
	      /* XXX use permissions from stat call */
	      chmod (config_tmp, sbuf.st_mode);
	    }
	  rename (config_tmp, conf_name.c_str());

	  return YCPBoolean(ret);
	}
      else
	{
	  string conf_name = string("/etc/pam.d/") + path->component_str(0);
	  struct pam_config data;
	  FILE *fout;
	  FILE *fp = fopen (conf_name.c_str(), "r");
	  char config_tmp[] = "/etc/pam.d/.YaST2.pam.agent.XXXXXX";
	  int fd;
	  struct stat sbuf;
	  if (fp == NULL)
	    {
	      y2warning ("unknown config file in path '%s'",
			 path->toString().c_str());
	      return YCPVoid();
	    }

	  fd =  mkstemp (config_tmp);
	  if (fd < 0)
	    {
	      y2error ("PamAgent::Write: cannot create tmp file");
	      return YCPVoid();
	    }
	  fout = fdopen (fd, "w");

	  memset (&data, 0, sizeof (data));

	  while (read_pam_config (fp, &data) > 0)
	    {
	      char *new_arg = NULL;

	      // If one of both is NULL, this cannot be our
	      // entry.
	      if (data.type == NULL || data.module == NULL)
		{
		  if (data.comments != NULL)
		    fprintf (fout, "#%s\n", data.comments);
		  free_pam_config (&data);
		  continue;
		}

	      // data.module can be a complete path to the module,
	      // but our interface only allows the name without path
	      // end ending .so suffix.
	      char *cp = strrchr (data.module, '/');
	      if (cp == NULL)
		cp = data.module;
	      else
		cp++;
	      cp = strdup (cp);
	      // Remove the ending ".so"
	      cp[strlen(cp) - 3] = '\0';

	      if (strcmp (data.type, path->component_str(1).c_str()) == 0 &&
		  strcmp (cp, path->component_str(2).c_str()) == 0)
		{
		  YCPMap entries;

		  if (data.type)
		    entries->add (YCPString ("type"), YCPString (data.type));
		  if (data.control)
		    entries->add (YCPString ("control"), YCPString (data.control));
		  if (data.module)
		    entries->add (YCPString ("module"), YCPString (data.module));
		  {
		    /* Modify arguments */

		    if (add)
		      new_arg = add_string (data.arguments, param);
		    else
		      new_arg = remove_string (data.arguments, param);

		    if (new_arg)
		      {
			entries->add (YCPString ("arguments"),
				      YCPString (new_arg));
			// free (new_arg);
		      }
		    ret = true;
		  }
		  if (data.comments)
		    entries->add (YCPString ("comments"),
				  YCPString (data.comments));
		}

	      fprintf (fout, "%s %s\t%s", data.type, data.control, data.module);
	      if (new_arg)
		fprintf (fout, "\t%s", new_arg);
	      else if (data.arguments)
		fprintf (fout, "\t%s", data.arguments);
	      if (data.comments)
		fprintf (fout, " #%s", data.comments);
	      fprintf (fout, "\n");

	      if (new_arg)
		free (new_arg);
	      free (cp);
	      free_pam_config (&data);
	    }
	  fclose (fout);
	  fclose (fp);
	  if (stat (conf_name.c_str(), &sbuf) == 0)
	    {
	      chown (config_tmp, sbuf.st_uid, sbuf.st_gid);
	      /* XXX use permissions from stat call */
	      chmod (config_tmp, sbuf.st_mode);
	    }
	  rename (config_tmp, conf_name.c_str());

	  return YCPBoolean(ret);
	}
    }
  y2error ("unknown command in path '%s'", path->toString().c_str());
  return YCPVoid();
}

/**
 * otherCommand
 */
YCPValue PamAgent::otherCommand(const YCPTerm& term)
{
    string sym = term->symbol()->symbol();

    if (sym == "PamAgent") {
        /* Your initialization */
        return YCPVoid();
    }

    return YCPNull();
}
