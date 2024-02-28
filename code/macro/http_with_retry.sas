/***********************************************************************/
/*  SAS Macro: http_with_retry.sas                                     */
/*  Description:                                                       */
/*    PROC HTTP call with retries.                                     */
/*    Sets global macro variables HTTP_RC and HTTP_SUCCESS             */
/*  Parameters:                                                        */
/*    URL:     Request URL                                             */
/*    METHOD:  HTTP method                                             */
/*    FILEREF: Filename for HTTP output                                */
/*    PAYLOAD: Payload as quoted string or filename                    */
/*    CT:      Content type                                            */
/*    RETRIES: Number of retries                                       */
/*    TOKEN:   Bearer token                                            */
/*    DELAY:   Time in seconds between retries                         */
/*    SUCCESS: Expected HTTP return code                               */
/*  Output                                                             */
/*    HTTP_RC:      Http return code (-1 if none was received)         */
/*    HTTP_SUCCESS: TRUE on success, FALSE on failure                  */
/*                                                                     */
/*  By: Simon Topp, SAS Institute                                      */
/*  Version: 1.2, October 2022                                         */
/***********************************************************************/

%macro http_with_retry(URL, FILEREF, PAYLOAD=, CT=, METHOD=GET, RETRIES=1, TOKEN=, DELAY=10, SUCCESS=200);
  %global HTTP_RC HTTP_SUCCESS;
  %local COUNT RC OPTIONS;
  %let COUNT=0;
  %let HTTP_RC=-1;
  %let HTTP_SUCCESS=FALSE;

  %let OPTIONS=method="%superq(METHOD)";

  /* payload ? */
  %if %sysevalf(%superq(PAYLOAD) ne,boolean) %then %do;
    %let OPTIONS = %superq(OPTIONS) in=%superq(PAYLOAD);
  %end;
  /* content type ? */
  %if %sysevalf(%superq(CT) ne,boolean) %then %do;
    %let OPTIONS = %superq(OPTIONS) ct="%superq(CT)";
  %end;
  /* token ? */
  %if %sysevalf(%superq(TOKEN) ne,boolean) %then %do;
    %let OPTIONS = %superq(OPTIONS) oauth_bearer="%superq(TOKEN)";
  %end;
  /* proxyhost ? */
  %if %symexist(PROXYHOST) %then %do;
    %let OPTIONS = %superq(OPTIONS) proxyhost="%superq(PROXYHOST)";
  %end;
  /* proxyport ? */
  %if %symexist(PROXYPORT) %then %do;
    %let OPTIONS = %superq(OPTIONS) proxyport=%superq(PROXYPORT);
  %end;

  %do %while(%superq(COUNT) <= %superq(RETRIES) and %superq(HTTP_RC) ne %superq(SUCCESS));
    %let COUNT = %eval(%superq(COUNT) + 1);
    %put NOTE: %sysfunc(ktranslate(%sysfunc(datetime(), e8601dt23.3), ' ', 'T'));
    %put NOTE: %superq(METHOD) %superq(URL);

    proc http clear_cache clear_cookies url="%superq(URL)" out=%superq(FILEREF) %unquote(%superq(OPTIONS));
    run;

    %put NOTE: %sysfunc(translate(%sysfunc(datetime(), e8601dt23.3), ' ', 'T'));

    /* check for return code */
    %if %symexist(SYS_PROCHTTP_STATUS_CODE) ne 1 %then %do;
      %put WARNING: Expected HTTP %superq(SUCCESS), but a response was not received from PROC HTTP;
      %let HTTP_RC = -1;
    %end;
    %else %do;
      %let HTTP_RC = %superq(SYS_PROCHTTP_STATUS_CODE);
      %if %superq(HTTP_RC) eq %superq(SUCCESS) %then %do;
        %put NOTE: Received HTTP %superq(HTTP_RC);
        %let HTTP_SUCCESS=TRUE;
      %end;
      %else %do;
        %put WARNING: Expected HTTP %superq(SUCCESS), but received HTTP %superq(HTTP_RC) %superq(SYS_PROCHTTP_STATUS_PHRASE);
        %if %sysfunc(fileref(%superq(FILEREF))) <= 0 %then %do;
          %if %sysfunc(fexist(%superq(FILEREF))) %then %do;
            %put Reply from %superq(URL):;
            data _null_;
              infile %superq(FILEREF);
              input;
              putlog _infile_;
            run;
          %end;
        %end;
      %end;
    %end;

    /* check for retry */
    %if %superq(HTTP_RC) ne %superq(SUCCESS) %then %do;
      %if %superq(COUNT) <= %superq(RETRIES) %then %do;
        %put NOTE: HTTP retry %superq(COUNT)/%superq(RETRIES) in %superq(DELAY) seconds;
        %let RC = %sysfunc(sleep(%superq(DELAY)));
      %end;
      %else %do;
        %put ERROR: %superq(COUNT) HTTP failure(s) - no more retries;
      %end;
    %end;
    %put;
  %end;
%mend http_with_retry;
