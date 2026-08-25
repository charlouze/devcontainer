- montage `agent-gh` absent : la connexion GitHub ne survivrait pas à la
  recréation du container, et il faudrait refaire `gh auth login` avant de
  pouvoir pousser ou ouvrir une PR
- montage `agent-playwright` absent : les navigateurs seraient retéléchargés à
  chaque rebuild du container
- ports publiés sur l'hôte : `forwardPorts` ouvre 4200 et 8080, et
  `portsAttributes` garde une entrée pour 4200. Plus rien ne se publie, et
  `otherPortsAttributes` manque pour couper le forward automatique
- commentaires du template absents
- tag d'image : `1`, déjà à jour
