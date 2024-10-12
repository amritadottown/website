---
layout: '@/layouts/BaseLayout.astro'
title: Resources
---

# Resources

> Good artists copy, great artists steal.  
> \- Pablo Picasso

We have attached some inspirations for you to look at and steal. Everything is free on the Indie Web but of course, you must make it your own, and pass it on. Use your own tools, or if you don't know where to start, we have a tools section for you to get started. The ideology section contains a bunch of articles for the people among you who are interested in going deeper down the rabbit hole of the Indie Web and fighting for a better space on the Internet.

## Tools For Making A Website

Here are some tools to help you get started on your website development. Remember, this is just a directory - consult the documentation on whatever you're interested in using to know more.

### Static Site Generators

These are tools that generate a complete static website from your Markdown or HTML files, according to a template that you can either build yourself or find on the internet. This works great for infrequently-updated sites like a personal internet home.

-   [hugo](https://gohugo.io) - a very popular SSG written in Go with a massive ecosystem of themes. Check out [https://themes.gohugo.io/](https://themes.gohugo.io/) - you may recognize some of these from around the web!
-   [astro](https://astro.build/) - a JavaScript-based SSG that uses the developer experience of React to build lightweight static websites, which works great for personal websites of all kinds. Take a look at their [themes](https://astro.build/themes/) page for templates you can use and iterate on.

We don't recommend:
- Server-rendered sites (Flask, Django, etc.): these are more difficult to host since they need a persistent backend server. 
- CMSes (WordPress, Ghost etc): the CMS is a large piece of software that you either have to worry about hosting and maintaining yourself, or give up control to a service provider.
- Frontend frameworks (React, Svelte, etc.): for a mostly content-based site like a personal website, these will simply increase client load times and resource consumption for little benefit.

SSGs are great because they output pure HTML and CSS files that can just be served from disk. Your website doesn't contain any backend code that runs on a server (unless you opt-in). Static hosting is extremely cheap to run, and there's many completely free services - called _Jamstack hosts_ - that you can use to deploy your website. If your website is on a service like GitHub, they can automatically deploy a new version of your website when you push changes.

-   [Neocities](https://neocities.org/) is an indie web-focused website host with a lovely tutorial.
-   [Cloudflare Pages](https://pages.cloudflare.com/)
-   [Vercel](https://vercel.com)
-   [Netlify](https://netlify.com)

These also offer _functions_ - a way for you to add a small amount of backend code to serve dynamic content. Frameworks like Astro can use this to let you build dynamic pages in a similar manner to static ones.

### Domains

A domain is an important step in establishing your identity online. There's a plethora of suffixes to choose from, though you can't go wrong with the classic .com or .net - just make sure to pick something you won't be embarrassed by later, since abandoning a domain is destructive. Acquiring a domain can be a sketchy affair full of hidden costs, so we recommend [Cloudflare Registrar](https://www.cloudflare.com/products/registrar/) or [Porkbun](https://porkbun.com/) for a minimally deceitful experience. You can also transfer your domain between registrars as you wish.

## Inspirations

Here's a bunch of websites for you to get inspired by.

-   [coryd.dev](https://coryd.dev/) - a great looking website that also has some nice features. he's added ways to automatically log the books, music and movie's he's been listening to. his 'links' page is a great thing to add for articles and essays you find interesting. the general aesthetic is very clean and minimal. he also has articles on how he implements these features.
-   [nadia.xyz](https://nadia.xyz/) - a simple website that gets the job done. nadia is an independent researcher. check out her [notes](https://nadia.xyz/notes/) page for her brief 'tweet-like' thoughts. A great place to just throw out ideas without having an entire blog post tied to them.
-   [colly.com](https://colly.com/) - a beautiful home page, with a timeline of his life illustrated with pictures and the year. what simon has done is create a vibrant map of his life. his journal is quite nice to scroll through, and a great way to illustrate how an expressive feed can be when you're not limited by social media.
-   [amalinalai's precipice](https://amalinalai.github.io/precipice/) - a neat little website filled with links to the stuff lina cares about. a fun website to click around through. check out her [bookshelf](https://amalinalai.github.io/precipice/bookshelf/) and her [about me](https://amalinalai.github.io/precipice/about/) pages, they're done in quite unique ways worth stealing.
-   [rknight.me](https://rknight.me/) - a great color scheme paired with a unique layout.
-   [savbrown.com](https://www.savbrown.com/) - an extremely minimal website that is as expressive as all the rest on this list. savvannah brown is a video essayist, and there's not much on this site, but what it does is provide a nice way to showcase herself. check out her [garden](https://www.savbrown.com/garden) which is a digital scrapbook of sorts, that's a fun idea to steal.
-   [rachsmith.com](https://rachsmith.com/) - very barebones articles view that works because of the nice layout it's presented in. open this in a browser for a very nice cursor effect

## Ideology

Here are a bunch of articles and essays that fuel our ideology, great for getting into the right mindset and understanding the large-scale movement that influences this one:

-   [what is to be done](https://www.cjthex.com/what-is-to-be-done/) - a manifesto to return to web 1.5, it is a larger call to quit social media but it highlights the beauty of the old web, and how personal it felt compared to today's corporate and sanitized digital landscape.
-   [indie web principles](https://indieweb.org/principles) - a set of principles to keep in mind when building your website and the motivation behind creating your website.
-   [manifesto for a humane web](https://humanewebmanifesto.com/) - essential reading for understanding the importance of what we're doing. it also contains great pointers for what your website should be doing, if you were lacking a clear vision.
-   [the internet is a series of webs](https://aramzs.xyz/essays/the-internet-is-a-series-of-webs/) - brings up some great points about link rot and our responsibility as website holders to link outwards.
-   [we need to rewild the internet](https://www.noemamag.com/we-need-to-rewild-the-internet/) - a great ecology based article on how ecosystems and how that works with digital ecosystems.
