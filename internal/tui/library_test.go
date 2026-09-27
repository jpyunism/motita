package tui

import (
	"io"
	"path/filepath"
	"testing"

	"github.com/madkoding/motita/internal/config"
	"github.com/madkoding/motita/internal/procedures"
	"github.com/madkoding/motita/internal/skills"
	"github.com/madkoding/motita/internal/usage"
)

// Front ends reach the library through the RUNNER, never by opening a second one: two
// libraries over one directory would each save their own view over the other's, which is
// the mistake the shared store exists to prevent.
func TestTheRunnerExposesTheLibraryItWasGiven(t *testing.T) {
	dir := t.TempDir()
	led, err := usage.Open(filepath.Join(dir, ".usage.json"))
	if err != nil {
		t.Fatalf("usage.Open: %v", err)
	}
	store := &procedures.Store{Library: skills.New(dir), Usage: led}
	r := NewAppRunner(io.Discard, io.Discard, config.Default(), nil, nil, nil)
	r.UseStore(store)

	if _, err := r.SaveSkill("One", "# One\n\nbody\n"); err != nil {
		t.Fatalf("SaveSkill: %v", err)
	}
	index, err := r.Skills()
	if err != nil {
		t.Fatalf("Skills: %v", err)
	}
	if len(index) != 1 || index[0].Name != "one" {
		t.Fatalf("Skills() = %+v, want one entry named one", index)
	}
	got, err := r.Skill("one")
	if err != nil || got.Body == "" {
		t.Fatalf("Skill(one) = %+v, %v; the body is what this is for", got, err)
	}
	// The provenance marker is a SECURITY decision: only created_by="agent" skills may be
	// archived or merged by the curator, so a save from the interface must never be
	// marked as the background fork's.
	if e := r.SkillTelemetry()["one"]; e.CreatedBy != usage.ByForeground {
		t.Errorf("a save from the interface must be provenance %q, not %q", usage.ByForeground, e.CreatedBy)
	}
	if err := r.SetSkillPinned("one", true); err != nil {
		t.Fatalf("SetSkillPinned: %v", err)
	}
	if !r.SkillTelemetry()["one"].Pinned {
		t.Error("the pin was not recorded in the sidecar")
	}
	if err := r.ArchiveSkill("one"); err != nil {
		t.Fatalf("ArchiveSkill: %v", err)
	}
	archived, err := r.ArchivedSkills()
	if err != nil || len(archived) != 1 || archived[0] != "one" {
		t.Fatalf("ArchivedSkills = %v, %v", archived, err)
	}
	if err := r.RestoreSkill("one"); err != nil {
		t.Fatalf("RestoreSkill: %v", err)
	}
	if _, err := r.Skill("one"); err != nil {
		t.Errorf("Skill after Restore: %v", err)
	}
}

// A runner whose ledger could not be opened still answers the list: the library is the
// feature, the telemetry is beside it.
func TestTheRunnerSurvivesWithoutALedger(t *testing.T) {
	dir := t.TempDir()
	r := NewAppRunner(io.Discard, io.Discard, config.Default(), nil, nil, nil)
	r.UseStore(&procedures.Store{Library: skills.New(dir), Usage: nil})

	if _, err := r.Skills(); err != nil {
		t.Errorf("Skills with no ledger: %v", err)
	}
	if err := r.SetSkillPinned("one", true); err == nil {
		t.Error("pinning with no ledger must be refused with a reason, not silently ignored")
	}
	if got := r.SkillTelemetry(); len(got) != 0 {
		t.Errorf("SkillTelemetry with no ledger = %v, want empty", got)
	}
	// Archive and restore still WORK without a ledger: the document moves, the
	// telemetry that would have recorded it simply is not there.
	if _, err := r.SaveSkill("two", "# Two\n\nbody\n"); err != nil {
		t.Fatalf("SaveSkill: %v", err)
	}
	if err := r.ArchiveSkill("two"); err != nil {
		t.Errorf("ArchiveSkill with no ledger: %v", err)
	}
	if err := r.RestoreSkill("two"); err != nil {
		t.Errorf("RestoreSkill with no ledger: %v", err)
	}
}

// TestTheRunnerReportsWhatTheLibraryRefuses: the three writes pass the library's answer
// through untouched. A front end shows the reason the LIBRARY gave ("the name is empty",
// "past the ...-byte limit"), not one this layer invented, because the library is the only
// thing that knows the rule.
func TestTheRunnerReportsWhatTheLibraryRefuses(t *testing.T) {
	dir := t.TempDir()
	led, err := usage.Open(filepath.Join(dir, ".usage.json"))
	if err != nil {
		t.Fatal(err)
	}
	r := NewAppRunner(io.Discard, io.Discard, config.Default(), nil, nil, nil)
	r.UseStore(&procedures.Store{Library: skills.New(dir), Usage: led})

	// A name that sanitises to nothing.
	if _, err := r.SaveSkill("!!!", "# X\n\nbody\n"); err == nil {
		t.Error("SaveSkill with an unusable name must fail")
	}
	// An empty body.
	if _, err := r.SaveSkill("fine", ""); err == nil {
		t.Error("SaveSkill with an empty body must fail")
	}
	// Archiving something that is not there, and restoring something that is not archived.
	if err := r.ArchiveSkill("nope"); err == nil {
		t.Error("ArchiveSkill on a missing document must fail")
	}
	if err := r.RestoreSkill("nope"); err == nil {
		t.Error("RestoreSkill on a document that is not archived must fail")
	}
}
