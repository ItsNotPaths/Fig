/* Ask PAM whether a password is this user's. The only file in fig that
 * knows what PAM is.
 *
 * The password arrives on stdin and never on a command line or in the
 * environment: both of those are readable in /proc by every other process
 * this user runs, and during a lock that is most of the session.
 *
 * It needs no privilege. pam_unix runs the setuid unix_chkpwd helper when it
 * cannot read /etc/shadow itself, which is how every screen locker works.
 *
 * Exit 0 means yes. Anything else means no.
 */
#include <pwd.h>
#include <security/pam_appl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define PW_MAX 1024

static char password[PW_MAX];

static int reply(int n, const struct pam_message **msg,
		 struct pam_response **out, void *data)
{
	struct pam_response *r = calloc((size_t)n, sizeof *r);
	int i;

	(void)data;
	if (!r)
		return PAM_BUF_ERR;

	for (i = 0; i < n; i++) {
		switch (msg[i]->msg_style) {
		case PAM_PROMPT_ECHO_OFF:
		case PAM_PROMPT_ECHO_ON:
			r[i].resp = strdup(password);
			if (!r[i].resp) {
				free(r);
				return PAM_BUF_ERR;
			}
			break;
		default:
			break;   /* info and error text go nowhere */
		}
	}
	*out = r;
	return PAM_SUCCESS;
}

/* Read stdin to the first newline or to the end, whichever comes first. */
static void read_password(void)
{
	size_t len = 0;

	while (len < sizeof password - 1) {
		ssize_t n = read(STDIN_FILENO, password + len,
				 sizeof password - 1 - len);
		if (n <= 0)
			break;
		len += (size_t)n;
	}
	password[len] = 0;
	password[strcspn(password, "\n")] = 0;
}

int main(void)
{
	static struct pam_conv conv = { reply, NULL };
	struct passwd *pw = getpwuid(getuid());
	pam_handle_t *pam = NULL;
	int rc;

	if (!pw)
		return 1;

	read_password();

	rc = pam_start("fig-auth", pw->pw_name, &conv, &pam);
	if (rc == PAM_SUCCESS)
		rc = pam_authenticate(pam, 0);
	if (rc == PAM_SUCCESS)
		rc = pam_acct_mgmt(pam, 0);

	if (pam)
		pam_end(pam, rc);

	explicit_bzero(password, sizeof password);
	return rc == PAM_SUCCESS ? 0 : 1;
}
