package catalog

type PackageCatalog struct {
	SchemaVersion int            `json:"schemaVersion"`
	Prerequisites []Prerequisite `json:"prerequisites"`
	Packages      []Package      `json:"packages"`
}

type Prerequisite struct {
	ID                   string   `json:"id"`
	Platform             string   `json:"platform"`
	Type                 string   `json:"type"`
	Architectures        []string `json:"architectures"`
	KeyringURL           string   `json:"keyringUrl"`
	KeyringSHA256        string   `json:"keyringSha256"`
	KeyringPath          string   `json:"keyringPath"`
	RepositoryBaseURL    string   `json:"repositoryBaseUrl"`
	RepositorySuite      string   `json:"repositorySuite"`
	RepositoryComponents []string `json:"repositoryComponents"`
	SourcesListPath      string   `json:"sourcesListPath"`
}

type Package struct {
	ID                   string                `json:"id"`
	Name                 string                `json:"name"`
	Description          string                `json:"description"`
	Tier                 string                `json:"tier"`
	Categories           []string              `json:"categories"`
	License              string                `json:"license"`
	Dependencies         []string              `json:"dependencies"`
	Conflicts            []string              `json:"conflicts"`
	Conditions           *Conditions           `json:"conditions,omitempty"`
	ConfigurationIntents []string              `json:"configurationIntents"`
	Providers            map[string][]Provider `json:"providers"`
}

type Conditions struct {
	DiskHeavy            *bool   `json:"diskHeavy,omitempty"`
	RestartMayBeRequired *bool   `json:"restartMayBeRequired,omitempty"`
	AuthorizedLabOnly    *bool   `json:"authorizedLabOnly,omitempty"`
	HardwareRecommended  *string `json:"hardwareRecommended,omitempty"`
}

type Provider struct {
	Manager         string    `json:"manager"`
	PackageID       string    `json:"packageId"`
	Source          string    `json:"source,omitempty"`
	Privilege       string    `json:"privilege"`
	Scope           string    `json:"scope"`
	Architectures   []string  `json:"architectures,omitempty"`
	PrerequisiteIDs []string  `json:"prerequisiteIds,omitempty"`
	Detection       Detection `json:"detection"`
	InstallOptions  []string  `json:"installOptions"`
	Estimate        Estimate  `json:"estimate"`
}

type Detection struct {
	Type string `json:"type"`
}

type Estimate struct {
	DownloadMBMin     float64 `json:"downloadMbMin"`
	DownloadMBMax     float64 `json:"downloadMbMax"`
	InstallMinutesMin float64 `json:"installMinutesMin"`
	InstallMinutesMax float64 `json:"installMinutesMax"`
}

type ProfileCatalog struct {
	SchemaVersion  int       `json:"schemaVersion"`
	CorePackageIDs []string  `json:"corePackageIds"`
	Packs          []Pack    `json:"packs"`
	Profiles       []Profile `json:"profiles"`
}

type Pack struct {
	ID         string   `json:"id"`
	Name       string   `json:"name"`
	PackageIDs []string `json:"packageIds"`
}

type Profile struct {
	ID                 string   `json:"id"`
	Name               string   `json:"name"`
	Extends            []string `json:"extends"`
	PackageIDs         []string `json:"packageIds"`
	RecommendedPackIDs []string `json:"recommendedPackIds"`
	OptionalPackIDs    []string `json:"optionalPackIds"`
}

type Catalogs struct {
	Packages         PackageCatalog
	Profiles         ProfileCatalog
	PackageByID      map[string]Package
	PrerequisiteByID map[string]Prerequisite
	PackByID         map[string]Pack
	ProfileByID      map[string]Profile
	CatalogSHA256    string
}
