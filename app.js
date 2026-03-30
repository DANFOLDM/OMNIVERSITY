const config = window.ELIMUCOIN_CONFIG || {};
const requestTimeoutMs = Number(config.requestTimeoutMs) || 5000;

const themeStorageKey = "elimucoin-theme";
const themeToggles = document.querySelectorAll(".theme-toggle");

const setThemeToggleLabel = (theme) => {
  const isDark = theme === "dark";
  themeToggles.forEach(toggle => {
    const icon = toggle.querySelector(".theme-toggle-icon");
    const text = toggle.querySelector(".theme-toggle-text");
    if (icon) icon.textContent = isDark ? "🌞" : "🌙";
    if (text) text.textContent = isDark ? "Light Mode" : "Dark Mode";
    toggle.setAttribute("aria-pressed", String(isDark));
  });
};

const applyTheme = (theme) => {
  const resolved = theme === "dark" ? "dark" : "light";
  if (resolved === "dark") {
    document.documentElement.setAttribute("data-theme", "dark");
  } else {
    document.documentElement.removeAttribute("data-theme");
  }
  setThemeToggleLabel(resolved);
};

const storedTheme = localStorage.getItem(themeStorageKey);
// Default to light if no preference or if we want to ensure it's white
const initialTheme = storedTheme === "dark" ? "dark" : "light";
applyTheme(initialTheme);

themeToggles.forEach(toggle => {
  toggle.addEventListener("click", () => {
    const isCurrentlyDark = document.documentElement.getAttribute("data-theme") === "dark";
    const nextTheme = isCurrentlyDark ? "light" : "dark";
    applyTheme(nextTheme);
    localStorage.setItem(themeStorageKey, nextTheme);
  });
});

const normalizeBase = (base) => (base || "").replace(/\/$/, "");
const fallbackBase = normalizeBase(config.fallbackBase);
const useDemoServer = Boolean(config.useDemoServer);

const apiBase = {
  sensei: normalizeBase(config.senseiBase),
  radar: normalizeBase(config.radarBase),
  biometric: normalizeBase(config.biometricBase)
};

if (useDemoServer && fallbackBase) {
  apiBase.sensei = fallbackBase;
  apiBase.radar = fallbackBase;
  apiBase.biometric = fallbackBase;
}

const statusPills = document.querySelectorAll(".status-pill");
const statusMap = {};
const dashAi = document.getElementById("dash-ai");
statusPills.forEach((pill) => {
  const key = pill.dataset.service;
  statusMap[key] = {
    dot: pill.querySelector(".status-dot"),
    text: pill.querySelector(".status-text")
  };
});

const updateAiStatus = () => {
  if (!dashAi) return;
  const services = ["sensei", "radar", "biometric"];
  const onlineCount = services.filter(
    (service) => statusMap[service] && statusMap[service].text.textContent === "Online"
  ).length;
  if (onlineCount === 3) {
    dashAi.textContent = "3 Online";
  } else if (onlineCount === 0) {
    dashAi.textContent = "Offline";
  } else {
    dashAi.textContent = `${onlineCount} Online`;
  }
};

const fetchJson = async (url, options = {}) => {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), requestTimeoutMs);
  try {
    const res = await fetch(url, {
      ...options,
      headers: {
        "Content-Type": "application/json",
        ...(options.headers || {})
      },
      signal: controller.signal
    });
    if (!res.ok) {
      const errText = await res.text();
      throw new Error(errText || "Request failed");
    }
    return await res.json();
  } finally {
    clearTimeout(timeout);
  }
};

const setStatus = (service, online) => {
  const entry = statusMap[service];
  if (!entry) return;
  entry.dot.classList.toggle("online", online);
  entry.dot.classList.toggle("offline", !online);
  entry.text.textContent = online ? "Online" : "Offline";
  updateAiStatus();
};

const checkService = async (service, baseUrl) => {
  if (!baseUrl) {
    setStatus(service, false);
    return;
  }
  try {
    await fetchJson(`${baseUrl}/health`);
    setStatus(service, true);
  } catch (err) {
    setStatus(service, false);
  }
};

const checkAllServices = () => {
  checkService("sensei", apiBase.sensei);
  checkService("radar", apiBase.radar);
  checkService("biometric", apiBase.biometric);
};

checkAllServices();
setInterval(checkAllServices, 20000);

const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

const revealItems = document.querySelectorAll(".reveal");
const counterItems = document.querySelectorAll("[data-counter]");
const isLanding = document.body && document.body.classList.contains("landing");
const menuLinks = document.querySelectorAll(".menu-link");
const menuSections = Array.from(menuLinks)
  .map((link) => link.getAttribute("href"))
  .filter((href) => href && href.startsWith("#"))
  .map((href) => document.querySelector(href))
  .filter(Boolean);

const setActiveMenu = (sectionId) => {
  menuLinks.forEach((link) => {
    const target = link.getAttribute("href");
    link.classList.toggle("active", target === `#${sectionId}`);
  });
};

const setCounters = () => {
  counterItems.forEach((el) => {
    el.textContent = el.dataset.counter;
  });
};

const animateCounter = (el) => {
  const target = Number(el.dataset.counter || 0);
  const duration = 1200;
  const start = performance.now();

  const tick = (now) => {
    const progress = Math.min((now - start) / duration, 1);
    const value = Math.floor(progress * target);
    el.textContent = value;
    if (progress < 1) requestAnimationFrame(tick);
  };

  requestAnimationFrame(tick);
};

if (!isLanding) {
  if (prefersReducedMotion) {
    revealItems.forEach((el) => el.classList.add("is-visible"));
    setCounters();
  } else {
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            observer.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.2 }
    );

    revealItems.forEach((el) => observer.observe(el));

    const counterObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            animateCounter(entry.target);
            counterObserver.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.6 }
    );

    counterItems.forEach((el) => counterObserver.observe(el));
  }
}

const updateActiveMenu = () => {
  if (!menuSections.length) return;
  const offset = 140;
  const scrollPos = window.scrollY + offset;
  let current = menuSections[0];
  menuSections.forEach((section) => {
    if (section.offsetTop <= scrollPos) {
      current = section;
    }
  });
  if (current) {
    setActiveMenu(current.id);
  }
};

let scrollTicking = false;
window.addEventListener("scroll", () => {
  if (scrollTicking) return;
  scrollTicking = true;
  window.requestAnimationFrame(() => {
    updateActiveMenu();
    scrollTicking = false;
  });
});
updateActiveMenu();

const setActiveByPath = () => {
  if (menuSections.length) return;
  const currentPath = window.location.pathname.split("/").pop() || "index.html";
  const currentHash = window.location.hash;
  menuLinks.forEach((link) => {
    const href = link.getAttribute("href") || "";
    if (href.startsWith("#")) return;
    const [target, hash] = href.split("#");
    if (target !== currentPath) {
      link.classList.remove("active");
      return;
    }
    if (!hash) {
      link.classList.toggle("active", !currentHash);
      return;
    }
    link.classList.toggle("active", currentHash === `#${hash}`);
  });
};
setActiveByPath();

const demoSenseiResponse =
  "Demo mode: AI Sensei is ready. Start the backend to see live responses.";
const demoJobs = [
  { title: "React Developer", match: "92%", location: "Remote" },
  { title: "Blockchain Engineer", match: "88%", location: "Nairobi" },
  { title: "AI Product Assistant", match: "84%", location: "Remote" }
];

const getUserId = () => {
  const input = document.getElementById("bio-user");
  return input && input.value.trim() ? input.value.trim() : "judge_demo";
};

let profileReady = false;
const ensureProfile = async () => {
  if (profileReady) return true;
  if (!apiBase.sensei) return false;
  const userId = getUserId();
  try {
    const existing = await fetchJson(`${apiBase.sensei}/profile/${userId}`);
    if (!existing.error) {
      profileReady = true;
      return true;
    }
    await fetchJson(`${apiBase.sensei}/profile`, {
      method: "POST",
      body: JSON.stringify({
        user_id: userId,
        name: "Judge Demo",
        email: "judge@elimucoin.test",
        learning_style: "visual",
        preferred_language: "en",
        learning_goals: ["Web Development", "Blockchain"]
      })
    });
    profileReady = true;
    return true;
  } catch (err) {
    return false;
  }
};

const senseiSend = document.getElementById("sensei-send");
const senseiInput = document.getElementById("sensei-input");
const senseiOutput = document.getElementById("sensei-output");

if (senseiSend && senseiInput && senseiOutput) {
  senseiSend.addEventListener("click", async () => {
    const message = senseiInput.value.trim();
    if (!message) return;
    senseiOutput.textContent = "Thinking...";
    senseiOutput.classList.remove("error", "success");

    const ready = await ensureProfile();
    if (!ready) {
      senseiOutput.textContent = demoSenseiResponse;
      senseiOutput.classList.add("error");
      return;
    }

    try {
      const response = await fetchJson(`${apiBase.sensei}/chat`, {
        method: "POST",
        body: JSON.stringify({ user_id: getUserId(), message })
      });
      const answer = response.response || "AI Sensei responded.";
      senseiOutput.textContent = answer;
      senseiOutput.classList.add("success");
    } catch (err) {
      senseiOutput.textContent = demoSenseiResponse;
      senseiOutput.classList.add("error");
    }
  });
}

const radarRun = document.getElementById("radar-run");
const radarSkills = document.getElementById("radar-skills");
const radarRole = document.getElementById("radar-role");
const radarOutput = document.getElementById("radar-output");

const parseSkillGraph = (input) => {
  const graph = {};
  input
    .split(",")
    .map((part) => part.trim())
    .forEach((pair) => {
      if (!pair) return;
      const [skill, level] = pair.split(":");
      if (skill && level) {
        graph[skill.trim()] = Number(level.trim()) || 1;
      }
    });
  if (Object.keys(graph).length === 0) {
    return { React: 4, Node: 3, JavaScript: 4 };
  }
  return graph;
};

const renderJobs = (jobs) => {
  const lines = jobs.map(
    (job) => `${job.title || job.role || "Role"} - ${job.match || ""} ${job.location || ""}`
  );
  return lines.join("\n");
};

if (radarRun && radarSkills && radarRole && radarOutput) {
  radarRun.addEventListener("click", async () => {
    radarOutput.textContent = "Matching...";
    radarOutput.classList.remove("error", "success");
    const graph = parseSkillGraph(radarSkills.value);
    const role = radarRole.value.trim() || "Full Stack Developer";

    if (!apiBase.radar) {
      radarOutput.textContent = renderJobs(demoJobs);
      radarOutput.classList.add("error");
      return;
    }

    try {
      const response = await fetchJson(`${apiBase.radar}/match`, {
        method: "POST",
        body: JSON.stringify({ user_id: getUserId(), skill_graph: graph, limit: 5 })
      });
      const jobs = response.jobs || [];
      radarOutput.textContent = jobs.length ? renderJobs(jobs) : "No matches yet.";
      radarOutput.classList.add("success");

      if (apiBase.radar) {
        fetchJson(`${apiBase.radar}/skill-recommendations`, {
          method: "POST",
          body: JSON.stringify({ skill_graph: graph, target_role: role })
        }).catch(() => {});
      }
    } catch (err) {
      radarOutput.textContent = renderJobs(demoJobs);
      radarOutput.classList.add("error");
    }
  });
}

const bioVerify = document.getElementById("bio-verify");
const bioType = document.getElementById("bio-type");
const bioOutput = document.getElementById("bio-output");

if (bioVerify && bioType && bioOutput) {
  bioVerify.addEventListener("click", async () => {
    bioOutput.textContent = "Verifying...";
    bioOutput.classList.remove("error", "success");

    if (!apiBase.biometric) {
      bioOutput.textContent = "Demo mode: biometric verification ready.";
      bioOutput.classList.add("error");
      return;
    }

    try {
      const payload = {
        user_id: getUserId(),
        verification_type: bioType.value,
        biometric_data: btoa("demo-biometric"),
        device_info: "judge_demo_device"
      };
      const response = await fetchJson(`${apiBase.biometric}/verify`, {
        method: "POST",
        body: JSON.stringify(payload)
      });
      bioOutput.textContent = response.status || response.message || "Verified";
      bioOutput.classList.add("success");
    } catch (err) {
      bioOutput.textContent = "Demo mode: biometric verification ready.";
      bioOutput.classList.add("error");
    }
  });
}
