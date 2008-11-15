%% This is the application resource file (.app fle) for the web_static,
%% application.
{application, web_static,
  [{description, "Static Web Application"},
   {vsn, "0.1.0"},
   {modules, [web_static_app,
              web_static_sup,
              web_static]},
   {registered, [web_static_sup]},
   {applications, [kernel, stdlib, mochiweb, web_pages, web_layout]},
   {mod, {web_static_app, []}},
   {start_phases, []}]}.
